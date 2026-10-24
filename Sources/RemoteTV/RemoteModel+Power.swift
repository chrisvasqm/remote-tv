import Foundation
import RemoteTVCore

extension RemoteModel {
    func turnOff() {
        guard let client else { return }
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
        guard !isWaking else { return }
        isWaking = true
        lastError = nil
        Task {
            defer { isWaking = false }
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(45)
            var attempt = 0
            while clock.now < deadline && status != .connected {
                // Repeat the packet a few times in case one is lost on Wi-Fi.
                if attempt < 3 {
                    do {
                        try WakeOnLAN.send(mac: mac, host: host)
                    } catch {
                        lastError = error.localizedDescription
                        return
                    }
                }
                attempt += 1
                try? await Task.sleep(for: .seconds(3))
                await connect()
            }
            if status != .connected {
                lastError = "The TV did not turn on. \(brand.wakeHelp)"
            }
        }
    }
}
