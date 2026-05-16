import Foundation
import AppKit

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var tags: [String]
    var notes: String
    var dateAdded: Date
    var clickCount: Int
    var faviconData: Data?
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String = "",
        url: String,
        tags: [String] = [],
        notes: String = "",
        dateAdded: Date = Date(),
        clickCount: Int = 0,
        faviconData: Data? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = tags
        self.notes = notes
        self.dateAdded = dateAdded
        self.clickCount = clickCount
        self.faviconData = faviconData
        self.isArchived = isArchived
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? urlDomain : title
    }

    var urlDomain: String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var faviconURL: URL? {
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme,
              let host = parsed.host else { return nil }
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }

    var faviconImage: NSImage? {
        guard let data = faviconData else { return nil }
        return NSImage(data: data)
    }
}
