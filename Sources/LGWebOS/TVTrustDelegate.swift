import CryptoKit
import Foundation
import Security

/// LG TVs serve a self-signed certificate on port 3001. The certificate is trusted only
/// for the configured TV address, and only if its public key matches the pin saved at
/// the first pairing (trust on first use). Without a pin, any certificate is accepted
/// once and its pin is recorded, so the pairing key is never sent to an impostor later.
final class TVTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let lock = NSLock()
    private var _expectedPin: String?
    private var _observedPin: String?
    private var _pinMismatch = false

    init(host: String, port: Int, expectedPin: String?) {
        self.host = host
        self.port = port
        self._expectedPin = expectedPin
    }

    /// Pins the certificate saved at pairing, so later connections on this session check it.
    func pin(_ pin: String) { lock.withLock { _expectedPin = pin } }

    /// The pin of the certificate the TV presented on this session.
    var observedPin: String? { lock.withLock { _observedPin } }
    /// True when the TV presented a certificate other than the pinned one.
    var pinMismatch: Bool { lock.withLock { _pinMismatch } }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host.caseInsensitiveCompare(host) == .orderedSame,
              space.port == port,
              let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let pin = Self.pin(of: trust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if let expectedPin = lock.withLock({ _expectedPin }), expectedPin != pin {
            lock.withLock { _pinMismatch = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        lock.withLock { _observedPin = pin }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// Never follow redirects: every request goes to the TV itself.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    /// SHA-256 of the leaf certificate's public key, hex encoded.
    private static func pin(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
