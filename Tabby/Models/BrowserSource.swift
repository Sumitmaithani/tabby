import Foundation

enum BrowserSource: String, CaseIterable, Identifiable, Codable {
    case chrome
    case arc
    case brave
    case edge
    case comet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave"
        case .edge: return "Edge"
        case .comet: return "Comet"
        }
    }

    /// Asset catalog image set name for import UI.
    var iconAssetName: String {
        switch self {
        case .chrome: return "BrowserChrome"
        case .arc: return "BrowserArc"
        case .brave: return "BrowserBrave"
        case .edge: return "BrowserEdge"
        case .comet: return "BrowserComet"
        }
    }

    /// Candidate bookmark paths, most common first (default profile only in v1.1).
    var bookmarkPathCandidates: [URL] {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        switch self {
        case .chrome:
            return [appSupport.appendingPathComponent("Google/Chrome/Default/Bookmarks", isDirectory: false)]
        case .arc:
            return [appSupport.appendingPathComponent("Arc/StorableSidebar.json", isDirectory: false)]
        case .brave:
            return [appSupport.appendingPathComponent("BraveSoftware/Brave-Browser/Default/Bookmarks", isDirectory: false)]
        case .edge:
            return [appSupport.appendingPathComponent("Microsoft Edge/Default/Bookmarks", isDirectory: false)]
        case .comet:
            // Current Comet installs use ~/Library/Application Support/Comet (Chromium layout).
            // Older docs referenced Perplexity/Comet — keep as fallback.
            return [
                appSupport.appendingPathComponent("Comet/Default/Bookmarks", isDirectory: false),
                appSupport.appendingPathComponent("Perplexity/Comet/Default/Bookmarks", isDirectory: false),
            ]
        }
    }

    /// Primary path for display; use `resolvedBookmarksURL()` for detection.
    var bookmarksPath: URL {
        bookmarkPathCandidates[0]
    }

    /// First candidate path that exists on disk, if any.
    func resolvedBookmarksURL(fileManager: FileManager = .default) -> URL? {
        bookmarkPathCandidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

struct BrowserScanResult: Identifiable, Equatable {
    var id: String { source.rawValue }
    let source: BrowserSource
    let isInstalled: Bool
    let isLocked: Bool
    let bookmarkCount: Int
    let parsed: ParsedImport?
    let error: ImportErrorKind?

    static func notInstalled(_ source: BrowserSource) -> BrowserScanResult {
        BrowserScanResult(
            source: source,
            isInstalled: false,
            isLocked: false,
            bookmarkCount: 0,
            parsed: nil,
            error: nil
        )
    }
}
