import Foundation
import Carbon

final class DataService {
    static let shared = DataService()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Directory setup

    func ensureStorageReady() {
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        let dirs = [
            Constants.Paths.appSupportURL,
            Constants.Paths.backupsDirectory
        ]
        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Storage URLs

    var bookmarksURL: URL { Constants.Paths.bookmarksFile }
    var tagsURL: URL { Constants.Paths.tagsFile }

    // MARK: - Load

    func loadBookmarks() -> [Bookmark] {
        load(from: bookmarksURL) ?? []
    }

    func loadTags() -> [Tag] {
        load(from: tagsURL) ?? []
    }

    // MARK: - Save

    func saveBookmarks(_ bookmarks: [Bookmark]) throws {
        try save(bookmarks, to: bookmarksURL)
    }

    func saveTags(_ tags: [Tag]) throws {
        try save(tags, to: tagsURL)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        var settings: AppSettings = load(from: Constants.Paths.settingsFile) ?? AppSettings()
        // Earlier builds used 0xB00 (⌘⇧⌥) by mistake; migrate to ⌘⇧.
        if settings.hotKeyModifiers == 0xB00 {
            settings.hotKeyModifiers = UInt32(cmdKey | shiftKey)
            try? saveSettings(settings)
        }
        return settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        try save(settings, to: Constants.Paths.settingsFile)
    }

    // MARK: - Helpers

    private func load<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        ensureStorageReady()
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomicWrite)
    }
}
