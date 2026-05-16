import Foundation

final class DataService {
    static let shared = DataService()

    private var useICloud = false
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

    func configure(useICloud: Bool) {
        self.useICloud = useICloud
        createDirectoriesIfNeeded()
    }

    func ensureStorageReady() {
        createDirectoriesIfNeeded()
        if useICloud, let icloud = Constants.Paths.iCloudURL {
            try? FileManager.default.createDirectory(at: icloud, withIntermediateDirectories: true)
        }
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

    // MARK: - Active storage URL

    var bookmarksURL: URL {
        if useICloud, let icloud = Constants.Paths.iCloudURL {
            return icloud.appendingPathComponent("bookmarks.json")
        }
        return Constants.Paths.bookmarksFile
    }

    var tagsURL: URL {
        if useICloud, let icloud = Constants.Paths.iCloudURL {
            return icloud.appendingPathComponent("tags.json")
        }
        return Constants.Paths.tagsFile
    }

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

    // MARK: - Settings (always local)

    func loadSettings() -> AppSettings {
        load(from: Constants.Paths.settingsFile) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) throws {
        try save(settings, to: Constants.Paths.settingsFile)
    }

    // MARK: - iCloud migration

    func migrateToICloud() throws {
        guard let icloud = Constants.Paths.iCloudURL else {
            throw DataError.iCloudUnavailable
        }
        let fm = FileManager.default
        try fm.createDirectory(at: icloud, withIntermediateDirectories: true)

        let pairs: [(URL, URL)] = [
            (Constants.Paths.bookmarksFile, icloud.appendingPathComponent("bookmarks.json")),
            (Constants.Paths.tagsFile, icloud.appendingPathComponent("tags.json"))
        ]
        for (local, remote) in pairs where fm.fileExists(atPath: local.path) {
            try? fm.removeItem(at: remote)
            try fm.copyItem(at: local, to: remote)
        }
    }

    func migrateFromICloud() throws {
        guard let icloud = Constants.Paths.iCloudURL else { return }
        let fm = FileManager.default
        let pairs: [(URL, URL)] = [
            (icloud.appendingPathComponent("bookmarks.json"), Constants.Paths.bookmarksFile),
            (icloud.appendingPathComponent("tags.json"), Constants.Paths.tagsFile)
        ]
        for (remote, local) in pairs where fm.fileExists(atPath: remote.path) {
            try? fm.removeItem(at: local)
            try fm.copyItem(at: remote, to: local)
        }
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

enum DataError: LocalizedError {
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Make sure you're signed in to iCloud and iCloud Drive is enabled."
        }
    }
}
