import Foundation
import RemoteTVCore

extension RemoteModel {
    func turnOff() {
        guard let client else { return }
        stopWaking()
        self.client = nil
        autoReconnect = false
        status = .unreachable
        resetTVState()
        Task {
            // The TV often drops the socket before answering; that still means it is off.
            try? await client.turnOff()
            await client.shutdown()
        }
    }

    /// Wakes the TV and keeps trying to connect while it starts, which takes about 10 seconds.
    func turnOn() {
        autoReconnect = true
        guard let mac = keyStore.mac(for: host) else {
            lastError = "Turn the TV on once with the remote so the app can learn its address."
            return
        }
        // A new press starts over, so it always sends fresh packets.
        wakeTask?.cancel()
        isWaking = true
        lastError = nil
        let target = host
        wakeTask = Task {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(45)
            var attempt = 0
            // Stops when the user turns the TV off, unpairs, picks another TV or presses again.
            @MainActor func keepTrying() -> Bool {
                guard !Task.isCancelled, clock.now < deadline, status != .connected else { return false }
                return autoReconnect && host == target
            }
            while keepTrying() {
                // Repeat the packet a few times in case one is lost on Wi-Fi.
                if attempt < 3 {
                    do {
                        try WakeOnLAN.send(mac: mac, host: target)
                    } catch {
                        guard !Task.isCancelled else { return }
                        lastError = error.localizedDescription
                        isWaking = false
                        return
                    }
                }
                attempt += 1
                try? await Task.sleep(for: .seconds(3))
                guard keepTrying() else { break }
                await connect()
            }
            guard !Task.isCancelled else { return }
            isWaking = false
            if status != .connected && autoReconnect && host == target {
                lastError = "The TV did not turn on. \(brand.wakeHelp)"
            }
        }
    }

    /// Ends a wake that is running, for Turn off, unpairing or another TV.
    func stopWaking() {
        wakeTask?.cancel()
        wakeTask = nil
        isWaking = false
    }
}
