import Foundation

/// Parsed League Client lockfile: `name:pid:port:password:protocol`.
struct Lockfile: Equatable {
    static let defaultPath = "/Applications/League of Legends.app/Contents/LoL/lockfile"

    let processName: String
    let pid: Int
    let port: Int
    let password: String
    let scheme: String

    init?(contents: String) {
        let parts = contents
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 5,
              !parts[0].isEmpty,
              let pid = Int(parts[1]),
              let port = Int(parts[2]), (1...65535).contains(port),
              !parts[3].isEmpty,
              parts[4] == "https" || parts[4] == "http"
        else { return nil }
        processName = parts[0]
        self.pid = pid
        self.port = port
        password = parts[3]
        scheme = parts[4]
    }

    /// HTTP Basic auth header used by the local League Client API (user is always `riot`).
    var authorizationHeader: String {
        "Basic " + Data("riot:\(password)".utf8).base64EncodedString()
    }

    var baseURL: URL {
        URL(string: "\(scheme)://127.0.0.1:\(port)")!
    }
}
