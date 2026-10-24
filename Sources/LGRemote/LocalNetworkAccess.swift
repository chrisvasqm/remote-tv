import AppKit
import dnssd
import Network

/// macOS asks for Local Network access the first time an app looks for devices
/// on the network. Browsing for a Bonjour service (declared in Info.plist under
/// NSBonjourServices) makes that prompt appear, and the browser's state tells
/// whether access was denied.
@MainActor
final class LocalNetworkAccess {
    private(set) var isDenied = false
    private var browser: NWBrowser?

    func check() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjour(type: "_lgremote._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))):
                    self?.isDenied = true
                case .ready:
                    self?.isDenied = false
                default:
                    break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }
}
