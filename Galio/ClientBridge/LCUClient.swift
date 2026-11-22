import Foundation

/// Where the League Client API lives (real client via lockfile, or the in-process mock server).
struct LCUEndpoint: Equatable {
    let baseURL: URL
    let authorization: String?

    init(baseURL: URL, authorization: String?) {
        self.baseURL = baseURL
        self.authorization = authorization
    }

    init(lockfile: Lockfile) {
        self.init(baseURL: lockfile.baseURL, authorization: lockfile.authorizationHeader)
    }

    var port: Int { baseURL.port ?? 0 }
}

enum LCUError: Error, Equatable {
    case http(status: Int, body: String)
    case invalidResponse
}

/// Thin REST client for the League Client API (LCU). Unsupported by Riot but widely used by
/// registered companions; Galio only reads state and performs the user-initiated conveniences
/// listed in docs/SPEC.md §2 (rune page import, summoner spells, item sets).
final class LCUClient {
    let endpoint: LCUEndpoint
    private let session: URLSession

    init(endpoint: LCUEndpoint, session: URLSession = RiotSession.shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func url(for path: String) -> URL {
        URL(string: path, relativeTo: endpoint.baseURL)?.absoluteURL ?? endpoint.baseURL
    }

    @discardableResult
    func request(_ method: String, _ path: String, json body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: url(for: path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = endpoint.authorization {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LCUError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LCUError.http(status: http.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let data = try await request("GET", path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func send<B: Encodable>(_ method: String, _ path: String, body: B) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        return try await request(method, path, json: data)
    }

    // MARK: - Typed endpoints

    func gameflowPhase() async throws -> GameflowPhase {
        let raw: String = try await get("/lol-gameflow/v1/gameflow-phase")
        return GameflowPhase(rawValue: raw) ?? .unknown
    }

    func gameflowSession() async throws -> GameflowSession {
        try await get("/lol-gameflow/v1/session")
    }

    func champSelectSession() async throws -> ChampSelectSession {
        try await get("/lol-champ-select/v1/session")
    }

    func pickableChampionIds() async throws -> [Int] {
        try await get("/lol-champ-select/v1/pickable-champion-ids")
    }

    func currentSummoner() async throws -> CurrentSummoner {
        try await get("/lol-summoner/v1/current-summoner")
    }

    func endOfGameStats() async throws -> EndOfGameStats {
        try await get("/lol-end-of-game/v1/eog-stats-block")
    }
}

/// Only the local player's own identifiers — needed for the item-set API. Never used for
/// other players.
struct CurrentSummoner: Decodable, Equatable {
    let summonerId: Int64
    let accountId: Int64?
    let puuid: String?
}
