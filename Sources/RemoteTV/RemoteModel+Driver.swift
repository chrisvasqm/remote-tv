import Foundation
import RemoteTVCore

extension RemoteModel {
    /// The one loop that talks to the TV in the background, for the app's lifetime.
    /// Each turn: apply screen changes, then connect or wake if needed, then refresh the
    /// live view while the panel is visible. Doing these in turn means a refresh never
    /// overlaps a screen change or a connect, and captures never overlap each other.
    ///
    /// Live view: frames are captured back to back, each download overlapping the next
    /// capture. Protected screens (black for 5 frames in a row) and the app/volume info
    /// are checked every 3 seconds or right after an action. While the TV is unreachable
    /// and the panel is open, it retries the connection every 10 seconds.
    func drive() async {
        let clock = ContinuousClock()
        let canCapture = brand.supports(.screenshot)
        var lastInfo = clock.now - .seconds(60)
        var lastConnect = clock.now - .seconds(60)
        var liveViewRunning = false
        while true {
            let started = clock.now
            await applyScreenChanges()
            if let plan = wake {
                await stepWake(plan, now: started)
            } else if status != .connected && wantsConnect(lastConnect: lastConnect, now: started) {
                lastConnect = started
                connectRequested = false
                await connect()
            } else if status == .connected && panelIsVisible {
                let due = refreshSoon || started - lastInfo >= .seconds(3)
                refreshSoon = false
                if due { lastInfo = started }
                // Independent requests: the info refresh doesn't hold up the next frame.
                async let info: Void = due ? refreshInfo() : ()
                if canCapture && (due || !screenIsProtected) {
                    liveViewRunning = true
                    await refreshScreen()
                }
                await info
            }
            if liveViewRunning && !panelIsVisible {
                // Drop a capture still in flight, so the next live view starts fresh.
                liveViewRunning = false
                await client?.dropPendingFrame()
            }
            // Start the next capture as soon as one finishes while the picture is live;
            // otherwise check once a second, or sooner when an intent nudges.
            let live = status == .connected && panelIsVisible && !screenIsProtected && canCapture
            let next = started + (live ? .milliseconds(20) : .seconds(1))
            if next > clock.now { await nudge.wait(upTo: next - clock.now) }
        }
    }

    private func wantsConnect(lastConnect: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Bool {
        guard !host.isEmpty, status != .connecting, status != .pairing else { return false }
        return connectRequested || (autoReconnect && panelIsVisible && now - lastConnect >= .seconds(10))
    }

    // MARK: - Connect

    /// Connects with a new client. A result that arrives after the client was replaced
    /// (another address, Turn off, Forget pairing) is ignored.
    func connect() async {
        let host = host
        dropClient()
        resetTVState()
        let client = brand.makeTV(host: host, keyStore: keyStore)
        await client.setDisconnectHandler { [weak self, weak client] in
            Task { @MainActor in
                if let client { self?.clientDropped(client) }
            }
        }
        self.client = client
        status = keyStore.key(for: host) == nil ? .pairing : .connecting
        do {
            try await client.connect()
            guard client === self.client else { return }
            status = .connected
            lastError = nil
            async let apps = client.apps()
            async let inputs = client.inputs()
            let (loadedApps, loadedInputs) = ((try? await apps) ?? [], (try? await inputs) ?? [])
            guard client === self.client else { return }
            self.apps = loadedApps
            self.inputs = loadedInputs
            await refreshInfo()
            // Learn the MAC on every connect, so a replaced TV or a reused address is picked up.
            if brand.supports(.wakeOnLAN), let mac = await WakeOnLAN.macAddress(for: host),
               mac != keyStore.mac(for: host) {
                keyStore.setMac(mac, for: host)
            }
        } catch {
            guard client === self.client else { return }
            log.error("connect to \(host, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            dropClient()
            // A TV's own answer (refused, timed out) can't be macOS blocking the network.
            let denied = error is TVError ? false : await LocalNetworkAccess.isDenied()
            status = denied ? .networkBlocked : .unreachable
            lastError = denied ? nil : error.localizedDescription
        }
    }

    // MARK: - Wake-on-LAN

    /// One step every 3 seconds: a packet for the first 3 steps (in case one is lost on
    /// Wi-Fi), and a connect from the second step on, while the TV starts.
    private func stepWake(_ plan: WakePlan, now: ContinuousClock.Instant) async {
        if status == .connected {
            wake = nil
            return
        }
        if now >= plan.deadline {
            wake = nil
            lastError = "The TV did not turn on. \(brand.wakeHelp)"
            return
        }
        guard now >= plan.nextStep else { return }
        var next = plan
        next.step += 1
        next.nextStep = now + .seconds(3)
        wake = next
        if plan.step > 0 { await connect() }
        // Turn off, Forget pairing or another address ended the wake meanwhile.
        guard wake == next, status != .connected, plan.step < 3 else { return }
        do {
            try WakeOnLAN.send(mac: plan.mac, host: plan.host)
        } catch {
            wake = nil
            lastError = error.localizedDescription
        }
    }

    // MARK: - Screen changes

    /// Applies the user's screen off/on changes in order. A refused change puts the old
    /// state back only if no newer change is waiting, since that one's state is shown.
    private func applyScreenChanges() async {
        while !screenChanges.isEmpty {
            let change = screenChanges.removeFirst()
            guard let client else { continue }
            do {
                if change.off { try? await client.pause() }
                try await client.setScreen(on: !change.off)
                guard client === self.client else { continue }
                refreshSoon = true
                lastError = nil
            } catch {
                guard client === self.client else { continue }
                if screenChanges.isEmpty { screenIsOff = change.previous }
                await report(error, from: client)
            }
        }
    }

    // MARK: - Live view

    func refreshInfo() async {
        guard let client else { return }
        do {
            async let app = client.foregroundAppId()
            async let volume = client.volume()
            async let screenOff = brand.supports(.screenOff) ? try? client.screenIsOff() : nil
            let (appId, level) = try await (app, volume)
            let off = await screenOff
            guard client === self.client else { return }
            // Assign only changes, so an unchanged TV doesn't redraw the panel every 3 seconds.
            if foregroundAppId != appId { foregroundAppId = appId }
            if self.volume != level { self.volume = level }
            // A change the user just asked for wins over what the TV said before it.
            if let off, screenChanges.isEmpty, screenIsOff != off { screenIsOff = off }
        } catch {
            await report(error, from: client)
        }
    }

    private func refreshScreen() async {
        guard let client else { return }
        do {
            let data: Data
            if !screenIsProtected {
                guard let next = try await client.nextFrame() else { return }
                data = next
            } else {
                await client.dropPendingFrame()
                framesPerSecond = nil
                data = try await client.screenshot()
            }
            guard client === self.client else { return }
            if data == lastFrame {
                // An unchanged black frame still counts toward "protected".
                if blackFrames > 0 { blackFrames += 1 }
            } else {
                guard let frame = await Frame.decode(data, width: PanelMetrics.previewWidth),
                      client === self.client else { return }
                lastFrame = data
                blackFrames = frame.isNearlyBlack ? blackFrames + 1 : 0
                screenshot = frame.image
                countFrame()
            }
            if screenIsProtected != (blackFrames >= 5) { screenIsProtected = blackFrames >= 5 }
        } catch {
            await report(error, from: client)
        }
    }

    private func countFrame() {
        let now = ContinuousClock.now
        frameTimes = frameTimes.filter { now - $0 < .seconds(3) } + [now]
        framesPerSecond = frameTimes.count > 1 ? Double(frameTimes.count) / 3 : nil
    }
}
