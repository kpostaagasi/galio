import Foundation
import Network

/// A recorded game scenario served by `MockServer` (see `Galio/Resources/Mock/*.json`).
/// Format: `{"name": ..., "description": ..., "routes": {"GET /lol-gameflow/v1/gameflow-phase": <json>, ...}}`
struct MockScenario {
    let name: String
    let description: String
    var routes: [String: Any]

    static let available = ["champselect", "champselect-locked", "ingame", "aram", "mayhem", "arena", "postgame"]

    init(name: String, description: String, routes: [String: Any]) {
        self.name = name
        self.description = description
        self.routes = routes
    }

    init?(json data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = obj["routes"] as? [String: Any]
        else { return nil }
        name = obj["name"] as? String ?? "custom"
        description = obj["description"] as? String ?? ""
        self.routes = routes
    }

    static func load(named name: String, bundle: Bundle = .main) -> MockScenario? {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Mock"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return MockScenario(json: data)
    }
}

/// Minimal HTTP/1.1 server on 127.0.0.1 that impersonates the League Client API and the Live
/// Client Data API from a `MockScenario`. Used by `--mock-game <scenario>`, the CI smoke test
/// and the unit tests. Supports stateful rune pages (GET/POST/PUT/DELETE `/lol-perks/v1/pages`)
/// and records every mutating request so tests can assert on client actions.
final class MockServer {
    struct RecordedRequest: Equatable {
        let method: String
        let path: String
        let body: String
    }

    private var scenario: MockScenario
    private let queue = DispatchQueue(label: "galio.mock-server")
    private var listener: NWListener?
    private let lock = NSLock()
    private var recorded: [RecordedRequest] = []
    private var pages: [[String: Any]]
    private var nextPageId = 900

    private(set) var port: UInt16 = 0

    init(scenario: MockScenario) {
        self.scenario = scenario
        pages = scenario.routes["GET /lol-perks/v1/pages"] as? [[String: Any]] ?? []
    }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func setRoute(_ key: String, _ value: Any) {
        lock.lock(); defer { lock.unlock() }
        scenario.routes[key] = value
    }

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback   // never reachable from the network
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.fire() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error), .waiting(let error):
                    if once.fire() { cont.resume(throwing: error) }
                case .cancelled:
                    if once.fire() { cont.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.port = port
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        read(conn, buffer: Data())
    }

    private func read(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let request = Self.parseRequest(buf) {
                let response = self.respond(to: request)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            } else if isComplete || error != nil || buf.count > 2_000_000 {
                conn.cancel()
            } else {
                self.read(conn, buffer: buf)
            }
        }
    }

    struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    /// Returns a request once headers and the full body (Content-Length) have arrived.
    static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var length = 0
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
        var path = String(requestLine[1])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        return HTTPRequest(method: String(requestLine[0]).uppercased(), path: path, body: Data(body))
    }

    private func respond(to req: HTTPRequest) -> Data {
        lock.lock()
        defer { lock.unlock() }
        if req.method != "GET" {
            recorded.append(RecordedRequest(method: req.method, path: req.path, body: String(decoding: req.body, as: UTF8.self)))
        }
        // Stateful rune pages.
        if req.path == "/lol-perks/v1/pages" {
            switch req.method {
            case "GET": return Self.http(200, json: pages)
            case "POST":
                var page = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
                page["id"] = nextPageId
                page["isDeletable"] = true
                page["isEditable"] = true
                nextPageId += 1
                if (page["current"] as? Bool) == true {
                    for i in pages.indices { pages[i]["current"] = false }
                }
                pages.append(page)
                return Self.http(200, json: page)
            default: break
            }
        }
        if req.path.hasPrefix("/lol-perks/v1/pages/"), let id = Int(req.path.split(separator: "/").last ?? "") {
            if req.method == "DELETE" {
                pages.removeAll { ($0["id"] as? Int) == id }
                return Self.http(204, json: nil)
            }
            if req.method == "PUT", var page = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any] {
                page["id"] = id
                pages.removeAll { ($0["id"] as? Int) == id }
                pages.append(page)
                return Self.http(200, json: page)
            }
        }
        if req.path == "/lol-perks/v1/currentpage", req.method == "GET" {
            return Self.http(200, json: pages.first { ($0["current"] as? Bool) == true } ?? pages.first ?? [:])
        }
        if let value = scenario.routes["\(req.method) \(req.path)"] {
            return Self.http(200, json: value)
        }
        if req.method != "GET" {
            return Self.http(204, json: nil)
        }
        return Self.http(404, json: ["errorCode": "RPC_ERROR", "httpStatus": 404, "message": "No mock route for \(req.path)"])
    }

    static func http(_ status: Int, json: Any?) -> Data {
        var body = Data()
        if let json {
            body = (try? JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])) ?? Data()
        }
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 404: reason = "Not Found"
        default: reason = "Status"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nConnection: close\r\n"
        head += "Content-Length: \(body.count)\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// Thread-safe one-shot flag.
final class OnceFlag {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Parses `--mock-game <scenario>` from the launch arguments.
enum MockLaunch {
    static var scenarioName: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--mock-game"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
