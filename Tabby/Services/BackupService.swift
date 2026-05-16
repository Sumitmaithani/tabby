import Foundation

final class BackupService {
    static let shared = BackupService()
    private let fm = FileManager.default

    private init() {}

    // MARK: - Create backup

    func backup(bookmarks: [Bookmark], tags: [Tag]) {
        let backupsDir = Constants.Paths.backupsDirectory
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let payload = BackupPayload(bookmarks: bookmarks, tags: tags, date: Date())
        guard let data = try? encoder.encode(payload) else { return }

        let url = backupsDir.appendingPathComponent("backup_\(timestamp).json")
        try? data.write(to: url, options: .atomicWrite)

        pruneOldBackups()
    }

    // MARK: - List backups

    func listBackups() -> [BackupInfo] {
        let dir = Constants.Paths.backupsDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("backup_") }
            .compactMap { url -> BackupInfo? in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let date = attrs?[.creationDate] as? Date ?? Date()
                return BackupInfo(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Restore from backup

    func restore(from url: URL) throws -> (bookmarks: [Bookmark], tags: [Tag]) {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        return (payload.bookmarks, payload.tags)
    }

    // MARK: - Delete backup

    func delete(backup: BackupInfo) throws {
        try fm.removeItem(at: backup.url)
    }

    // MARK: - Prune

    private func pruneOldBackups() {
        let backups = listBackups()
        let excess = backups.dropFirst(Constants.maxBackups)
        for backup in excess {
            try? fm.removeItem(at: backup.url)
        }
    }
}

struct BackupPayload: Codable {
    let bookmarks: [Bookmark]
    let tags: [Tag]
    let date: Date
}

struct BackupInfo: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date

    var displayName: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
