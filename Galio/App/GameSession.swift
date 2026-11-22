import Foundation

/// Central coordinator: finds the League Client, tracks the gameflow phase (WebSocket events
/// with a 2 s polling fallback), reads champ select, polls the Live Client Data API while the
/// game is in progress and captures the end-of-game summary.
@MainActor
final class GameSession: ObservableObject {
    static let shared = GameSession()

    enum Connection: Equatable {
        case clientClosed
        case connected(port: Int)
        case mock(String)

        var isConnected: Bool { self != .clientClosed }
    }

    @Published private(set) var connection: Connection = .clientClosed
    @Published private(set) var phase: GameflowPhase = .none
    @Published private(set) var mode: ModeInfo?
    @Published private(set) var champSelect: ChampSelectSession?
    @Published private(set) var pickableChampionIds: Set<Int> = []
    /// The local player's own champion mastery (champion key → points).
    @Published private(set) var mastery: [Int: Int] = [:]
    @Published private(set) var live: LiveGameData?
    /// Last live snapshot of the finished game (for the post-game summary).
    @Published private(set) var lastLive: LiveGameData?
    @Published private(set) var endOfGame: EndOfGameStats?
    @Published private(set) var websocketActive = false
    @Published private(set) var lastError: String?
    /// Position from champ select / live data, kept for the post-game summary.
    @Published private(set) var lastPosition: Position?
    /// History record created for the game that just ended.
    @Published private(set) var lastRecord: GameRecord?

    private(set) var lcu: LCUClient?
    private var liveClient = LiveClient()
    private let socket = LCUWebSocket()
    private var loopTask: Task<Void, Never>?
    private var mockServer: MockServer?
    private(set) var mockScenarioName: String?
    /// Simulated OCR lines for the augment panel in mock scenarios.
    private(set) var mockAugmentOffer: [String] = []
    private var lastChampSelectFetch = Date.distantPast

    /// Called on every phase change (overlay auto-show, history capture).
    var onPhaseChange: ((GameflowPhase, GameflowPhase) -> Void)?

    var lockfilePath: String {
        let custom = UserDefaults.standard.string(forKey: "lockfilePath") ?? ""
        return custom.isEmpty ? Lockfile.defaultPath : custom
    }

    init() {
        socket.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        socket.onStateChange = { [weak self] connected in
            Task { @MainActor in self?.websocketActive = connected }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            if let name = MockLaunch.scenarioName {
                await self?.startMock(named: name)
            }
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        socket.disconnect()
        mockServer?.stop()
    }

    var isMock: Bool { mockServer != nil }

    func startMock(named name: String) async {
        guard let scenario = MockScenario.load(named: name) else {
            lastError = "Unknown mock scenario: \(name)"
            return
        }
        await startMock(scenario)
    }

    func startMock(_ scenario: MockScenario) async {
        let server = MockServer(scenario: scenario)
        do {
            _ = try await server.start()
        } catch {
            lastError = "Mock server failed: \(error.localizedDescription)"
            return
        }
        mockServer = server
        mockScenarioName = scenario.name
        mockAugmentOffer = scenario.augmentOffer
        lcu = LCUClient(endpoint: LCUEndpoint(baseURL: server.baseURL, authorization: nil))
        liveClient = LiveClient(baseURL: server.baseURL)
        connection = .mock(scenario.name)
        await tick()
    }

    // MARK: - Polling

    func tick() async {
        if mockServer == nil { refreshEndpoint() }
        guard let lcu else { return }
        do {
            let newPhase = try await lcu.gameflowPhase()
            lastError = nil
            await apply(phase: newPhase)
        } catch {
            if mockServer == nil {
                // The lockfile can outlive a crashed client; treat as closed until it answers again.
                lastError = error.localizedDescription
                await apply(phase: .none)
            }
            return
        }
        if mode == nil, phase != .none, phase != .lobby {
            mode = try? await lcu.gameflowSession().mode
        }
        if phase == .champSelect {
            // Socket events keep this fresh; poll at most every 2 s as fallback.
            if !websocketActive || Date().timeIntervalSince(lastChampSelectFetch) > 6 {
                await refreshChampSelect()
            }
        }
        if phase.isInGame {
            await refreshLive()
        }
    }

    private func refreshEndpoint() {
        let endpoint: LCUEndpoint?
        if let text = try? String(contentsOfFile: lockfilePath, encoding: .utf8), let lf = Lockfile(contents: text) {
            endpoint = LCUEndpoint(lockfile: lf)
        } else {
            endpoint = ProcessArgsLocator.findEndpoint()
        }
        guard let endpoint else {
            if lcu != nil || connection != .clientClosed {
                lcu = nil
                socket.disconnect()
                connection = .clientClosed
                resetGameState()
                let old = phase
                phase = .none
                if old != .none { onPhaseChange?(old, .none) }
            }
            return
        }
        if lcu?.endpoint != endpoint {
            lcu = LCUClient(endpoint: endpoint)
            connection = .connected(port: endpoint.port)
            socket.connect(endpoint)
        } else if !socket.isConnected, Int.random(in: 0..<5) == 0 {
            socket.connect(endpoint)   // occasional reconnect attempt
        }
    }

    private func resetGameState() {
        mode = nil
        champSelect = nil
        live = nil
        pickableChampionIds = []
    }

    func apply(phase newPhase: GameflowPhase) async {
        let old = phase
        guard newPhase != old else { return }
        phase = newPhase
        switch newPhase {
        case .none, .lobby, .matchmaking:
            resetGameState()
            if newPhase == .lobby, let lcu { mode = try? await lcu.gameflowSession().mode }
        case .champSelect:
            endOfGame = nil
            lastRecord = nil
            lastLive = nil
            lastPosition = nil
            if let lcu { mode = try? await lcu.gameflowSession().mode }
            await refreshChampSelect()
            if let lcu, let ids = try? await lcu.pickableChampionIds() { pickableChampionIds = Set(ids) }
            if mastery.isEmpty, let lcu, let list = try? await lcu.ownMastery() {
                mastery = Dictionary(list.map { ($0.championId, $0.championPoints) }, uniquingKeysWith: max)
            }
        case .inProgress, .gameStart, .reconnect:
            if mode == nil, let lcu { mode = try? await lcu.gameflowSession().mode }
        case .waitingForStats, .preEndOfGame, .endOfGame:
            if let live { lastLive = live }
            live = nil
            champSelect = nil
            if let lcu, let eog = try? await lcu.endOfGameStats(), eog.localPlayer != nil { endOfGame = eog }
            recordHistory()
        default:
            break
        }
        onPhaseChange?(old, newPhase)
    }

    func refreshChampSelect() async {
        guard let lcu else { return }
        lastChampSelectFetch = Date()
        if let session = try? await lcu.champSelectSession() {
            champSelect = session
            if let pos = session.myPosition { lastPosition = pos }
        }
    }

    private func refreshLive() async {
        do {
            let data = try await liveClient.allGameData()
            live = data
            lastLive = data
            if lastPosition == nil, let pos = Position(lcu: data.me?.position) { lastPosition = pos }
            if mode == nil || mode?.family == .other { mode = data.mode }
        } catch {
            // Loading screen: the API answers 404 until the game has started.
        }
    }

    /// Refetches the end-of-game block (used by the post-game view's retry button).
    func refreshEndOfGame() async {
        guard let lcu else { return }
        if let eog = try? await lcu.endOfGameStats(), eog.localPlayer != nil {
            endOfGame = eog
            recordHistory()
        }
    }

    /// Saves (or updates) the finished game in the local history.
    func recordHistory() {
        guard let record = HistoryStore.makeRecord(eog: endOfGame, live: lastLive, mode: mode, position: lastPosition,
                                                   store: DataStore.shared) else { return }
        let history = HistoryStore.shared
        if let previous = lastRecord, previous.id != record.id, previous.date.timeIntervalSinceNow > -3600 {
            history.delete([previous.id])
        }
        history.upsert(record)
        lastRecord = record
    }

    // MARK: - WebSocket events

    private func handle(_ event: LCUEvent) {
        switch event.uri {
        case "/lol-gameflow/v1/gameflow-phase":
            if let data = event.data, let raw = try? JSONDecoder().decode(String.self, from: data) {
                let p = GameflowPhase(rawValue: raw) ?? .unknown
                Task { await apply(phase: p) }
            }
        case "/lol-champ-select/v1/session":
            if event.eventType == "Delete" {
                champSelect = nil
            } else if let data = event.data, let session = try? JSONDecoder().decode(ChampSelectSession.self, from: data) {
                champSelect = session
                if let pos = session.myPosition { lastPosition = pos }
                lastChampSelectFetch = Date()
            }
        case "/lol-gameflow/v1/session":
            if let data = event.data, let session = try? JSONDecoder().decode(GameflowSession.self, from: data),
               session.gameData?.queue?.id != nil {
                mode = session.mode
            }
        default:
            break
        }
    }

    // MARK: - Derived

    /// The local player's champion id (champ select pick/hover, or live game champion).
    func myChampion(in store: DataStore) -> ChampionInfo? {
        if let live, let me = live.me { return store.champion(liveId: me.championDataId, name: me.championName) }
        if let cs = champSelect, cs.myChampionId != 0 { return store.champion(key: cs.myChampionId) }
        if let last = lastLive?.me, phase.isPostGame { return store.champion(liveId: last.championDataId, name: last.championName) }
        if let eog = endOfGame?.localPlayer, phase.isPostGame { return store.champion(key: eog.championId) }
        return nil
    }
}

/// Fallback when the lockfile is not at the default path: read the League client's own
/// command-line flags (`--app-port`, `--remoting-auth-token`) via `ps`. This only inspects
/// process arguments — never process memory.
enum ProcessArgsLocator {
    private static var lastCheck = Date.distantPast
    private static var cached: LCUEndpoint?

    static func findEndpoint() -> LCUEndpoint? {
        if Date().timeIntervalSince(lastCheck) < 10 { return cached }
        lastCheck = Date()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-ww", "-o", "args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { cached = nil; return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        cached = text.split(separator: "\n").lazy.compactMap { parse(commandLine: String($0)) }.first
        return cached
    }

    static func parse(commandLine line: String) -> LCUEndpoint? {
        guard line.contains("LeagueClientUx") else { return nil }
        func value(_ flag: String) -> String? {
            guard let r = line.range(of: "--\(flag)=") else { return nil }
            let rest = line[r.upperBound...]
            let end = rest.firstIndex(where: { $0 == " " || $0 == "\"" }) ?? rest.endIndex
            return String(rest[..<end])
        }
        guard let portText = value("app-port"), let port = Int(portText),
              let token = value("remoting-auth-token"), !token.isEmpty,
              let url = URL(string: "https://127.0.0.1:\(port)")
        else { return nil }
        let auth = "Basic " + Data("riot:\(token)".utf8).base64EncodedString()
        return LCUEndpoint(baseURL: url, authorization: auth)
    }
}
