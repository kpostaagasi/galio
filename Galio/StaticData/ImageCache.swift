import AppKit
import CryptoKit
import SwiftUI

/// Memory + disk cache for remote icons (Data Dragon / CommunityDragon).
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private let directory: URL

    init(directory: URL = AppPaths.caches.appendingPathComponent("images", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 600
    }

    static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    func image(for url: URL) async -> NSImage? {
        if let img = memory.object(forKey: url as NSURL) { return img }
        if let task = inflight[url] { return await task.value }
        let file = directory.appendingPathComponent(Self.fileName(for: url))
        let task = Task<NSImage?, Never> {
            if let data = try? Data(contentsOf: file), let img = NSImage(data: data) { return img }
            guard let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: result.0)
            else { return nil }
            try? result.0.write(to: file, options: .atomic)
            return img
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// AsyncImage replacement backed by `ImageCache`.
struct CachedImage: View {
    let url: URL?
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.18))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageCache.shared.image(for: url)
        }
    }
}
