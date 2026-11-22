import Foundation

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Galio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func subdirectory(_ name: String) -> URL {
        let dir = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("com.kpostaagasi.galio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct DataManifest: Codable, Equatable {
    let schema: Int
    let latest: String
    let generatedAt: String?
    let files: [String: String]?
}

enum PatchVersion {
    /// Numeric comparison of "16.23.1"-style versions.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Loads Galio's recommendation data: on-disk cache → bundled fallback, then refreshes from
/// `raw.githubusercontent.com/kpostaagasi/galio/main/data/` when a newer patch is published.
@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()
    nonisolated static let supportedSchema = 1
    static let remoteBase = URL(string: "https://raw.githubusercontent.com/kpostaagasi/galio/main/data/")!

    enum Source: String { case none, bundled, cache, remote }

    @Published private(set) var data: GalioDataSet?
    @Published private(set) var source: Source = .none
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var refreshError: String?
    @Published private(set) var isRefreshing = false
    /// Latest Data Dragon patch (used for image URLs).
    @Published private(set) var ddragonPatch: String?

    private(set) var championsByKey: [Int: ChampionInfo] = [:]
    private(set) var championsById: [String: ChampionInfo] = [:]
    private(set) var itemsById: [Int: ItemInfo] = [:]
    private(set) var runesById: [Int: RuneInfo] = [:]
    private(set) var stylesById: [Int: RuneStyle] = [:]
    private(set) var shardsById: [Int: RuneShard] = [:]
    private(set) var summonersById: [Int: SummonerSpellInfo] = [:]

    let cacheDir: URL
    let bundle: Bundle

    init(cacheDir: URL = AppPaths.subdirectory("data"), bundle: Bundle = .main) {
        self.cacheDir = cacheDir
        self.bundle = bundle
    }

    var patch: String { data?.patch ?? "?" }
    var imagePatch: String { ddragonPatch ?? data?.patch ?? "16.23.1" }

    // MARK: - Decoding

    nonisolated static func decode(_ raw: Data) throws -> GalioDataSet {
        let set = try JSONDecoder().decode(GalioDataSet.self, from: raw)
        guard set.schema == supportedSchema else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unsupported schema \(set.schema)"))
        }
        return set
    }

    nonisolated static func loadBest(cacheDir: URL, bundle: Bundle) -> (GalioDataSet, Source)? {
        let cached = (try? Data(contentsOf: cacheDir.appendingPathComponent("all.json"))).flatMap { try? decode($0) }
        let bundled = bundle.url(forResource: "all", withExtension: "json", subdirectory: "BundledData")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decode($0) }
        switch (cached, bundled) {
        case let (c?, b?): return PatchVersion.isNewer(b.patch, than: c.patch) ? (b, .bundled) : (c, .cache)
        case let (c?, nil): return (c, .cache)
        case let (nil, b?): return (b, .bundled)
        default: return nil
        }
    }

    // MARK: - Loading

    func loadInitial() {
        guard data == nil else { return }
        if let best = Self.loadBest(cacheDir: cacheDir, bundle: bundle) {
            install(best.0, source: best.1)
        }
    }

    func install(_ set: GalioDataSet, source: Source) {
        data = set
        self.source = source
        championsByKey = Dictionary(set.champions.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        championsById = Dictionary(set.champions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        itemsById = Dictionary(set.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var runes: [Int: RuneInfo] = [:]
        var styles: [Int: RuneStyle] = [:]
        for style in set.runes.styles {
            styles[style.id] = style
            for slot in style.slots { for r in slot { runes[r.id] = r } }
        }
        runesById = runes
        stylesById = styles
        shardsById = Dictionary(set.runes.shards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        summonersById = Dictionary(set.summoners.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Checks the published manifest and downloads a newer data set if available.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refreshError = nil
        async let dd: String? = DDragon.latestVersion()
        do {
            let (mdata, _) = try await URLSession.shared.data(from: Self.remoteBase.appendingPathComponent("manifest.json"))
            let manifest = try JSONDecoder().decode(DataManifest.self, from: mdata)
            if manifest.schema == Self.supportedSchema,
               force || data == nil || PatchVersion.isNewer(manifest.latest, than: patch) {
                let path = manifest.files?["all"] ?? "\(manifest.latest)/all.json"
                let (raw, _) = try await URLSession.shared.data(from: Self.remoteBase.appendingPathComponent(path))
                let set = try await Task.detached { try Self.decode(raw) }.value
                try? raw.write(to: cacheDir.appendingPathComponent("all.json"), options: .atomic)
                try? mdata.write(to: cacheDir.appendingPathComponent("manifest.json"), options: .atomic)
                install(set, source: .remote)
            }
            lastRefresh = Date()
        } catch {
            refreshError = error.localizedDescription
        }
        if let v = await dd { ddragonPatch = v }
    }

    // MARK: - Lookups

    func champion(key: Int) -> ChampionInfo? { championsByKey[key] }

    /// Resolves a Live Client champion (raw id like "MonkeyKing" or a display name).
    func champion(liveId: String?, name: String) -> ChampionInfo? {
        if let liveId, let c = championsById[liveId] { return c }
        let lower = name.lowercased()
        return data?.champions.first { $0.name.lowercased() == lower || $0.nameTR.lowercased() == lower }
    }

    func detail(for champion: ChampionInfo) -> ChampionDetail? { data?.details[champion.id] }

    func augments(for mode: ModeInfo) -> [AugmentInfo] {
        switch mode.family {
        case .arena: return data?.augments["ARENA"] ?? []
        case .aramMayhem: return data?.augments["MAYHEM"] ?? []
        default: return []
        }
    }
}

/// Data Dragon access with an on-disk cache per patch.
enum DDragon {
    static let base = URL(string: "https://ddragon.leagueoflegends.com")!

    static func latestVersion() async -> String? {
        guard let result = try? await URLSession.shared.data(from: base.appendingPathComponent("api/versions.json")),
              let list = try? JSONDecoder().decode([String].self, from: result.0)
        else { return nil }
        return list.first
    }

    static var locale: String { Loc.isTurkish ? "tr_TR" : "en_US" }

    /// Fetches `cdn/<patch>/data/<locale>/<file>` with a disk cache under Application Support.
    static func cachedJSON(patch: String, file: String, locale: String = DDragon.locale) async throws -> Data {
        let dir = AppPaths.subdirectory("ddragon/\(patch)/\(locale)")
        let local = dir.appendingPathComponent(file.replacingOccurrences(of: "/", with: "_"))
        if let data = try? Data(contentsOf: local) { return data }
        let url = base.appendingPathComponent("cdn/\(patch)/data/\(locale)/\(file)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LCUError.invalidResponse }
        try? data.write(to: local, options: .atomic)
        return data
    }

    static func champion(id: String, patch: String) async throws -> DDChampion? {
        let data = try await cachedJSON(patch: patch, file: "champion/\(id).json")
        return try JSONDecoder().decode(DDChampionFile.self, from: data).data[id]
    }

    // MARK: image URLs
    static func championIcon(_ id: String, patch: String) -> URL { base.appendingPathComponent("cdn/\(patch)/img/champion/\(id).png") }
    static func itemIcon(_ id: Int, patch: String) -> URL { base.appendingPathComponent("cdn/\(patch)/img/item/\(id).png") }
    static func spellIcon(_ file: String, patch: String) -> URL { base.appendingPathComponent("cdn/\(patch)/img/spell/\(file)") }
    static func passiveIcon(_ file: String, patch: String) -> URL { base.appendingPathComponent("cdn/\(patch)/img/passive/\(file)") }
    static func runeIcon(_ path: String) -> URL { base.appendingPathComponent("cdn/img/\(path)") }
    static func augmentIcon(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(string: "https://raw.communitydragon.org/latest/game/\(path)")
    }
}

struct DDChampionFile: Decodable { let data: [String: DDChampion] }

struct DDChampion: Decodable {
    struct Image: Decodable { let full: String }
    struct Spell: Decodable, Identifiable {
        let id: String
        let name: String
        let description: String
        let image: Image
        let cooldownBurn: String?
    }
    struct Passive: Decodable {
        let name: String
        let description: String
        let image: Image
    }
    let id: String
    let name: String
    let title: String
    let spells: [Spell]
    let passive: Passive
}
