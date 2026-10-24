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
    func turnScreenOff() {
        setScreenOff(true) {
            try? await $0.pause()
            try await $0.setScreen(on: false)
        }
    }

    func turnScreenOn() {
        setScreenOff(false) { try await $0.setScreen(on: true) }
    }

    /// Shows the new screen state at once, and puts the old one back if the TV refuses.
    private func setScreenOff(_ off: Bool, _ action: @escaping (any TV) async throws -> Void) {
        guard client != nil else { return }
        let previous = screenIsOff
        screenIsOff = off
        screenChangeInFlight = true
        run(action, onSuccess: { $0.screenChangeInFlight = false }, onFailure: {
            $0.screenChangeInFlight = false
            if $0.screenIsOff == off { $0.screenIsOff = previous }
        })
    }

    /// Runs an action on the current client. The callbacks run only if that client is
    /// still the current one; a result from a replaced client says nothing about the new one.
    private func run(
        _ action: @escaping (any TV) async throws -> Void,
        onSuccess: ((RemoteModel) -> Void)? = nil,
        onFailure: ((RemoteModel) -> Void)? = nil
    ) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                guard client === self.client else { return }
                onSuccess?(self)
                refreshSoon = true
                lastError = nil
            } catch {
                if client === self.client { onFailure?(self) }
                await report(error, from: client)
            }
        }
    }
}
