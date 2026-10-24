import Foundation
import RemoteTVCore

extension RemoteModel {
    func press(_ key: RemoteKey) { run { try await $0.press(key) } }
    func launch(_ app: TVApp) { run { try await $0.launch(app) } }
    func switchInput(_ input: TVInput) { run { try await $0.switchInput(input) } }
    func play() { run { try await $0.play() } }
    func pause() { run { try await $0.pause() } }
    func stop() { run { try await $0.stop() } }
    func volumeUp() { run { try await $0.volumeUp() } }
    func volumeDown() { run { try await $0.volumeDown() } }
    func toggleMute() { run { [muted = volume?.muted ?? false] in try await $0.setMute(!muted) } }
    func showMessage(_ text: String) {
        run({ try await $0.showMessage(text) }, onSuccess: { $0.lastMessageSent = text })
    }

    func closeForegroundApp() {
        guard !isHome, let id = foregroundAppId else { return }
        run { try await $0.close(appId: id) }
    }

    /// Pauses what is playing and turns the picture off, leaving the TV on.
    func turnScreenOff() { setScreenOff(true) }

    func turnScreenOn() { setScreenOff(false) }

    /// Shows the new screen state at once; the driver sends it to the TV in order.
    private func setScreenOff(_ off: Bool) {
        guard client != nil else { return }
        screenChanges.append(ScreenChange(off: off, previous: screenIsOff))
        screenIsOff = off
        nudge.fire()
    }

    /// Runs an action on the current client. `onSuccess` runs only if that client is still
    /// the current one; a result from a replaced client says nothing about the new one.
    private func run(
        _ action: @escaping (any TV) async throws -> Void,
        onSuccess: ((RemoteModel) -> Void)? = nil
    ) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                guard client === self.client else { return }
                onSuccess?(self)
                refreshSoon = true
                nudge.fire()
                lastError = nil
            } catch {
                await report(error, from: client)
            }
        }
    }
}
