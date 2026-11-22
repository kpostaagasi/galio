import Foundation

/// Watches whether the League Client is running by polling its lockfile.
@MainActor
final class ClientMonitor: ObservableObject {
    enum Status: Equatable {
        case clientClosed
        case clientOpen(port: Int)

        var title: String {
            switch self {
            case .clientClosed: return "League istemcisi kapalı"
            case .clientOpen: return "League istemcisi açık"
            }
        }

        var detail: String {
            switch self {
            case .clientClosed: return "League of Legends'ı açtığında Galio otomatik bağlanacak."
            case .clientOpen(let port): return "Yerel istemci arayüzü bulundu (port \(port))."
            }
        }

        var isOpen: Bool { if case .clientOpen = self { return true } else { return false } }
    }

    @Published private(set) var status: Status = .clientClosed
    private var timer: Timer?
    private let path: String

    init(path: String = Lockfile.defaultPath) {
        self.path = path
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        status = Self.status(forLockfileAt: path)
    }

    nonisolated static func status(forLockfileAt path: String) -> Status {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let lockfile = Lockfile(contents: text)
        else { return .clientClosed }
        return .clientOpen(port: lockfile.port)
    }
}
