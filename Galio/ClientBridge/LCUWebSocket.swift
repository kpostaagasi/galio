import Foundation

/// One `OnJsonApiEvent` message from the League Client WAMP socket.
struct LCUEvent {
    let uri: String
    let eventType: String
    /// Re-serialised JSON of the event's `data` field (nil for `Delete` events / null data).
    let data: Data?

    /// Parses `[8, "OnJsonApiEvent", {"uri": ..., "eventType": ..., "data": ...}]`.
    static func parse(_ text: String) -> LCUEvent? {
        guard let raw = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) as? [Any],
              array.count >= 3,
              (array[0] as? Int) == 8,
              let payload = array[2] as? [String: Any],
              let uri = payload["uri"] as? String
        else { return nil }
        let type = payload["eventType"] as? String ?? "Update"
        var data: Data?
        if let value = payload["data"], !(value is NSNull) {
            data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        return LCUEvent(uri: uri, eventType: type, data: data)
    }
}

/// Subscribes to League Client events over its local WebSocket (WAMP 1.0 style:
/// `[5, "OnJsonApiEvent"]`). Failures are expected (client restarting, mock server without
/// WebSocket support) — the caller keeps polling either way.
final class LCUWebSocket: NSObject {
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var connectedFlag = false

    var onEvent: ((LCUEvent) -> Void)?
    var onStateChange: ((Bool) -> Void)?

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return connectedFlag
    }

    private func setConnected(_ value: Bool) {
        lock.lock()
        let changed = connectedFlag != value
        connectedFlag = value
        lock.unlock()
        if changed { onStateChange?(value) }
    }

    static func socketURL(for endpoint: LCUEndpoint) -> URL? {
        guard var comps = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path = "/"
        return comps.url
    }

    func connect(_ endpoint: LCUEndpoint) {
        disconnect()
        guard let url = Self.socketURL(for: endpoint) else { return }
        var req = URLRequest(url: url)
        if let auth = endpoint.authorization {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let task = RiotSession.shared.webSocketTask(with: req)
        self.task = task
        task.resume()
        task.send(.string("[5,\"OnJsonApiEvent\"]")) { [weak self] error in
            if error == nil { self?.setConnected(true) } else { self?.setConnected(false) }
        }
        receive(on: task)
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setConnected(false)
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.task === task else { return }
            switch result {
            case .success(let message):
                let text: String?
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8)
                @unknown default: text = nil
                }
                if let text, !text.isEmpty, let event = LCUEvent.parse(text) {
                    self.onEvent?(event)
                }
                self.receive(on: task)
            case .failure:
                self.setConnected(false)
            }
        }
    }
}
