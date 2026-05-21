import Foundation

// MARK: - Format

enum ImportFormat: String, CaseIterable {
    case html
    case csv
    case json
    case md
    case txt

    var displayName: String {
        switch self {
        case .html: return "HTML"
        case .csv: return "CSV"
        case .json: return "JSON"
        case .md: return "Markdown"
        case .txt: return "Plain text"
        }
    }

    var expectedExtensions: [String] {
        switch self {
        case .html: return ["html", "htm"]
        case .csv: return ["csv"]
        case .json: return ["json"]
        case .md: return ["md", "markdown"]
        case .txt: return ["txt"]
        }
    }
}

// MARK: - Duplicate policy

enum DuplicatePolicy: String, Codable, CaseIterable, Identifiable {
    case skip = "Skip"
    case updateTitle = "Update title"
    case keepBoth = "Keep both"

    var id: String { rawValue }
}

// MARK: - Folder tree (HTML import)

struct FolderNode {
    var path: [String]
    var bookmarks: [Bookmark] = []
    var children: [FolderNode] = []

    /// `Work/Design/Inspiration` → `work.design.inspiration`
    static func flattenTag(from path: [String]) -> String {
        path
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
            .joined(separator: ".")
    }

    func flattenedBookmarks() -> [(bookmark: Bookmark, folderTag: String)] {
        var result: [(Bookmark, String)] = []
        let tag = Self.flattenTag(from: path)
        for b in bookmarks {
            var bookmark = b
            if !tag.isEmpty {
                bookmark.tags = [tag]
            }
            result.append((bookmark, tag))
        }
        for child in children {
            result.append(contentsOf: child.flattenedBookmarks())
        }
        return result
    }

    func folderCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        let tag = Self.flattenTag(from: path)
        if !tag.isEmpty, !bookmarks.isEmpty {
            counts[tag, default: 0] += bookmarks.count
        }
        for child in children {
            for (k, v) in child.folderCounts() {
                counts[k, default: 0] += v
            }
        }
        return counts
    }
}

// MARK: - Parse / plan / result

struct FailedRow: Identifiable, Equatable {
    let id = UUID()
    let line: Int
    let raw: String
    let reason: String
}

struct ParsedImport: Equatable {
    let format: ImportFormat
    let bookmarks: [Bookmark]
    let detectedFolders: [String: Int]
    let failedRows: [FailedRow]
    let sourceFilename: String
    let sourceHash: String?
    let totalBytes: Int

    var bookmarkCount: Int { bookmarks.count }
    var folderCount: Int { detectedFolders.count }
}

struct ImportPlan {
    let parsed: ParsedImport
    /// `nil` = import all folders
    let selectedFolders: Set<String>?
    let renamedTags: [String: String]
    let policy: DuplicatePolicy
}

struct ImportResult: Equatable {
    let imported: Int
    let updated: Int
    let tagsCreated: Int
    let duplicatesSkipped: Int
    let failedRows: [FailedRow]
    let backupURL: URL?
}

// MARK: - Errors

enum ImportErrorKind: Error, Equatable {
    case unsupportedFormat
    case malformed(format: ImportFormat, detail: String)
    case emptyFile
    case fileTooLarge(count: Int)
    case permissionDenied
    case diskFull
    case unknown(filename: String, detail: String)

    var userFacingLabel: String {
        switch self {
        case .unsupportedFormat: return "Unsupported format"
        case .malformed(let format, _): return "Malformed \(format.displayName)"
        case .emptyFile: return "Empty file"
        case .fileTooLarge: return "File too large"
        case .permissionDenied: return "Permission denied"
        case .diskFull: return "Disk full"
        case .unknown: return "Unknown error"
        }
    }
}

// MARK: - Re-import history (Opt-B)

struct ImportHistoryEntry: Codable, Equatable {
    let hash: String
    let filename: String
    let byteCount: Int
    let date: Date
}

struct ImportHistoryFile: Codable {
    var entries: [ImportHistoryEntry]
}

// MARK: - Crash recovery lock (Opt-A)

struct ImportLockPayload: Codable {
    let filename: String
    let startedAt: Date
    let bookmarkCount: Int
}

// MARK: - Browser import tags (leaf-only)

enum BrowserImportTagging {
    /// Chromium synthetic root folder names (normalized) — never used as leaf tags.
    static let legacyRootSegments: Set<String> = [
        "bookmarks-bar", "bookmark-bar", "other", "other-bookmarks",
        "mobile-bookmarks", "synced"
    ]

    static func normalizeFolderSegment(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    static func isChromiumSystemRootFolder(_ name: String) -> Bool {
        legacyRootSegments.contains(normalizeFolderSegment(name))
    }

    /// Deepest user folder in path, or nil if bookmark sits on the bar / other root.
    static func leafTag(fromFolderPath path: [String]) -> String? {
        guard let last = path.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty else {
            return nil
        }
        if legacyRootSegments.contains(last) { return nil }
        return last
    }

    /// Collapse legacy dot-notation import tags to a single leaf segment.
    static func migrateLegacyTag(_ tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(".") {
            let parts = trimmed.split(separator: ".").map { normalizeFolderSegment(String($0)) }
            let filtered = parts.filter { !legacyRootSegments.contains($0) }
            guard let last = filtered.last, !last.isEmpty else { return nil }
            return last
        }

        if legacyRootSegments.contains(normalizeFolderSegment(trimmed)) { return nil }
        return normalizeFolderSegment(trimmed)
    }
}
