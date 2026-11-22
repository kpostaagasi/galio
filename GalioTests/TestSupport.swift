import XCTest
@testable import Galio

final class BundleToken {}

enum Fixture {
    struct Missing: Error { let name: String }

    static func url(_ name: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        let ns = name as NSString
        guard let url = bundle.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension, subdirectory: "Fixtures")
        else { throw Missing(name: name) }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

/// Loads the bundled Galio data set once for all advisor tests.
enum TestData {
    static let set: GalioDataSet = {
        guard let best = DataStore.loadBest(cacheDir: URL(fileURLWithPath: "/nonexistent-galio-cache"), bundle: .main) else {
            fatalError("Bundled data set missing from the app bundle")
        }
        return best.0
    }()

    @MainActor
    static func store() -> DataStore {
        let s = DataStore(cacheDir: FileManager.default.temporaryDirectory.appendingPathComponent("galio-test-cache-\(UUID().uuidString)"), bundle: .main)
        s.install(set, source: .bundled)
        return s
    }

    static func champion(_ id: String) -> ChampionInfo {
        guard let c = set.champions.first(where: { $0.id == id }) else { fatalError("no champion \(id)") }
        return c
    }
}
