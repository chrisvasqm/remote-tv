import AppKit
import Network

/// macOS asks for Local Network access the first time an app looks for devices
/// on the network. Browsing for a Bonjour service (declared in Info.plist under
/// NSBonjourServices) is the reliable way to make that prompt appear.
@MainActor
final class LocalNetworkAccess {
    private var browser: NWBrowser?

    func requestPrompt() {
        let browser = NWBrowser(for: .bonjour(type: "_lgremote._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .main)
        self.browser = browser
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.browser?.cancel()
            self?.browser = nil
        }
    }

    static func isDenied(_ error: Error) -> Bool {
        (error as? URLError)?.code == .notConnectedToInternet
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }
}
