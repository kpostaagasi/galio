import Foundation
import Security

/// TLS handling for the two local Riot endpoints (League Client API and Live Client Data API).
///
/// Both serve self-signed certificates on 127.0.0.1. We first try to validate the chain against
/// Riot's published root (`riotgames.pem`, bundled from developer.riotgames.com). If that fails
/// we still accept the certificate, but **only** for loopback hosts — nothing else ever gets a
/// relaxed trust decision, so remote traffic (Data Dragon, GitHub) keeps the system defaults.
final class RiotTLSDelegate: NSObject, URLSessionDelegate {
    static let shared = RiotTLSDelegate()

    private let riotRoot: SecCertificate?
    /// Whether the last loopback handshake was validated against the bundled Riot root.
    private(set) var lastHandshakePinned = false

    override init() {
        riotRoot = Self.loadRiotRoot()
        super.init()
    }

    static func loadRiotRoot(bundle: Bundle = .main) -> SecCertificate? {
        guard let url = bundle.url(forResource: "riotgames", withExtension: "pem"),
              let pem = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return certificate(fromPEM: pem)
    }

    static func certificate(fromPEM pem: String) -> SecCertificate? {
        let body = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// Validates `trust` against the Riot root only (no hostname check: the certs are issued for
    /// "127.0.0.1"/"rclient" and do not carry a usable SAN).
    func evaluatePinned(_ trust: SecTrust) -> Bool {
        guard let root = riotRoot else { return false }
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, [root] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        return SecTrustEvaluateWithError(trust, nil)
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              Self.isLoopback(space.host),
              let trust = space.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        lastHandshakePinned = evaluatePinned(trust)
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum RiotSession {
    /// Shared session for loopback Riot APIs. Short timeouts: the endpoints are local.
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: RiotTLSDelegate.shared, delegateQueue: nil)
    }()
}
