import Foundation

/// LG TVs serve a self-signed certificate on port 3001. Trust it only for the
/// configured TV address; every other host keeps the system's normal checks.
final class TVTrustDelegate: NSObject, URLSessionDelegate {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == host,
              space.port == 3001,
              let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
