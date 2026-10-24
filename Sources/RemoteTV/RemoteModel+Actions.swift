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
        setScreenOff(true) { tv in
            // Don't wait for the pause: a TV that ignores it would hold up the screen for 10 s.
            Task { try? await tv.pause() }
            try await tv.setScreen(on: false)
        }
    }

    func turnScreenOn() {
        setScreenOff(false) { try await $0.setScreen(on: true) }
    }

    /// Shows the new screen state at once, and puts the old one back if the TV refuses,
    /// unless a newer screen change started meanwhile.
    private func setScreenOff(_ off: Bool, _ action: @escaping (any TV) async throws -> Void) {
        guard let client else { return }
        let previous = screenIsOff
        screenIsOff = off
        screenRequestsStarted += 1
        screenRequestsRunning += 1
        let request = screenRequestsStarted
        Task {
            defer { screenRequestsRunning -= 1 }
            do {
                try await action(client)
                guard client === self.client else { return }
                refreshSoon = true
                lastError = nil
            } catch {
                if client === self.client, screenRequestsStarted == request { screenIsOff = previous }
                await report(error, from: client)
            }
        }
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
                lastError = nil
            } catch {
                await report(error, from: client)
            }
        }
    }
}
