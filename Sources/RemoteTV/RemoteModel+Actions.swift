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
        run { [weak self] client in
            try await client.showMessage(text)
            await MainActor.run { self?.lastMessageSent = text }
        }
    }

    func closeForegroundApp() {
        guard !isHome, let id = foregroundAppId else { return }
        run { try await $0.close(appId: id) }
    }

    /// Pauses what is playing and turns the picture off, leaving the TV on.
    func turnScreenOff() {
        screenIsOff = true
        run {
            try? await $0.pause()
            try await $0.setScreen(on: false)
        }
    }

    func turnScreenOn() {
        screenIsOff = false
        run { try await $0.setScreen(on: true) }
    }

    private func run(_ action: @escaping (any TV) async throws -> Void) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                refreshSoon = true
                lastError = nil
            } catch {
                await report(error, from: client)
            }
        }
    }
}
