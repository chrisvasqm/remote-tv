import Foundation
import RemoteTVCore

extension RemoteModel {
    func turnOff() {
        wake = nil
        autoReconnect = false
        connectRequested = false
        guard let client else { return }
        self.client = nil
        status = .unreachable
        resetTVState()
        Task {
            // The TV often drops the socket before answering; that still means it is off.
            try? await client.turnOff()
            await client.shutdown()
        }
    }

    /// Wakes the TV and keeps trying to connect while it starts, which takes about 10 seconds.
    /// A new press starts over, so it always sends fresh packets.
    func turnOn() {
        autoReconnect = true
        guard let mac = keyStore.mac(for: host) else {
            lastError = "Turn the TV on once with the remote so the app can learn its address."
            return
        }
        lastError = nil
        let now = ContinuousClock.now
        wake = WakePlan(host: host, mac: mac, deadline: now + .seconds(45), nextStep: now)
        nudge.fire()
    }
}
