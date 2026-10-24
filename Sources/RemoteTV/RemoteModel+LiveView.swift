import Foundation
import RemoteTVCore

extension RemoteModel {
    /// Live view while the panel is visible: frames are captured back to back, each
    /// download overlapping the next capture, so requests never pile up on the TV.
    /// Protected screens (black for 5 frames in a row) are checked with the app/volume
    /// info, every 3 seconds or right after an action. When the TV is
    /// unreachable it retries the connection every 10 seconds.
    func panelVisibilityChanged(_ visible: Bool) {
        if visible {
            startPolling()
        } else {
            stopPolling()
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        let previous = stoppingPoll
        stoppingPoll = nil
        // Holds the model strongly; stopPolling() cancels the loop when the panel closes.
        pollTask = Task {
            // The TV captures every frame into the same file, so let a capture of the old
            // loop finish first. Capped, so a slow request can't freeze the reopened panel.
            if let previous { await Self.wait(for: previous, upTo: .seconds(1)) }
            let clock = ContinuousClock()
            var lastInfo = clock.now - .seconds(60)
            var lastConnect = clock.now - .seconds(60)
            let canCapture = brand.supports(.screenshot)
            while !Task.isCancelled {
                let started = clock.now
                switch status {
                case .connected:
                    let due = refreshSoon || started - lastInfo >= .seconds(3)
                    refreshSoon = false
                    if due { lastInfo = started }
                    // Independent requests: the info refresh doesn't hold up the next frame.
                    async let info: Void = due ? refreshInfo() : ()
                    if canCapture && (due || !screenIsProtected) { await refreshScreen() }
                    await info
                case .idle, .unreachable, .networkBlocked:
                    if autoReconnect && started - lastConnect >= .seconds(10) {
                        lastConnect = started
                        await connect()
                    }
                case .connecting, .pairing:
                    break
                }
                // Start the next capture as soon as one finishes while the picture
                // is live; everything else ticks once a second.
                let live = status == .connected && !screenIsProtected && canCapture
                let interval: Duration = live ? .milliseconds(20) : .seconds(1)
                try? await Task.sleep(until: started + interval, clock: clock)
            }
            // Drop a capture still in flight, so the next live view starts fresh.
            await client?.dropPendingFrame()
        }
    }

    private func stopPolling() {
        // The panel can report "hidden" twice; keep the loop that is still ending.
        guard let pollTask else { return }
        pollTask.cancel()
        stoppingPoll = pollTask
        self.pollTask = nil
    }

    private static func wait(for task: Task<Void, Never>, upTo limit: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    func refreshInfo() async {
        guard let client else { return }
        let generation = screenGeneration
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
            if let off, screenGeneration == generation, screenIsOff != off { screenIsOff = off }
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
