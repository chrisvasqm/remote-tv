import AppKit
import dnssd
import Network

/// macOS asks for Local Network access the first time an app looks for devices
/// on the network. Browsing for a Bonjour service (declared in Info.plist under
/// NSBonjourServices) makes that prompt appear, and the browser's state tells
/// whether access was denied.
enum LocalNetworkAccess {
    /// Starts a short Bonjour browse and reports whether macOS denied it.
    /// The first call also makes macOS show its permission prompt.
    static func isDenied() async -> Bool {
        // A placeholder service, the same for every brand: browsing for anything listed
        // in NSBonjourServices (scripts/bundle.sh) is what makes macOS ask. Keep the two in step.
        let browser = NWBrowser(for: .bonjour(type: "_lgremote._tcp", domain: nil), using: .tcp)
        defer { browser.cancel() }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))):
                    once.resume(true)
                case .ready, .failed, .cancelled:
                    once.resume(false)
                default:
                    break
                }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { once.resume(false) }
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Resumes a continuation at most once; browser callbacks and the timeout race.
private final class Once: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
