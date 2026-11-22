import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

/// On-device recognition of the three augment card titles (ARAM Mayhem / Arena).
/// Runs only when the player presses "Scan cards"; the screenshot never leaves the Mac and is
/// discarded right after text recognition. Needs the Screen Recording permission.
enum AugmentOCR {
    enum OCRError: Error, Equatable {
        case permissionDenied
        case noDisplay
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (once); returns whether access is granted now.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Captures the League game window (or the main display), recognises text and fuzzy-matches
    /// augment names.
    static func scan(augments: [AugmentInfo]) async throws -> [FuzzyMatcher.Match] {
        guard hasPermission else { throw OCRError.permissionDenied }
        let image = try await captureGameImage()
        let lines = try recognizeText(in: image)
        return FuzzyMatcher.match(lines: lines.map(\.text), augments: augments)
    }

    static func captureGameImage() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        let filter: SCContentFilter
        if let game = content.windows.first(where: { isGameWindow($0) }) {
            filter = SCContentFilter(desktopIndependentWindow: game)
            config.width = Int(game.frame.width * 2)
            config.height = Int(game.frame.height * 2)
        } else {
            let mainID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
                throw OCRError.noDisplay
            }
            let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingWindows: own)
            config.width = display.width * 2
            config.height = display.height * 2
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func isGameWindow(_ w: SCWindow) -> Bool {
        let app = w.owningApplication?.applicationName ?? ""
        let bundle = w.owningApplication?.bundleIdentifier ?? ""
        return (app == "League of Legends" || bundle.contains("riotgames.leagueoflegends")) && w.frame.width > 640
    }

    struct Line: Equatable {
        let text: String
        /// Normalised bounding box (Vision coordinates, origin bottom-left).
        let box: CGRect
    }

    /// Vision text recognition (Turkish + English), keeping lines in the central band where the
    /// augment cards are drawn.
    static func recognizeText(in image: CGImage) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.minimumTextHeight = 0.012
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { obs -> Line? in
            guard let top = obs.topCandidates(1).first, top.confidence > 0.3 else { return nil }
            let box = obs.boundingBox
            guard box.midY > 0.15, box.midY < 0.9 else { return nil }
            return Line(text: top.string, box: box)
        }
    }
}
