import Foundation

final class ImportService {
    static let shared = ImportService()
    private init() {}

    enum ImportFormat {
        case json, csv, html
    }

    func detectFormat(url: URL) -> ImportFormat? {
        switch url.pathExtension.lowercased() {
        case "json": return .json
        case "csv":  return .csv
        case "html", "htm": return .html
        default: return nil
        }
    }

    func importBookmarks(from url: URL) throws -> (bookmarks: [Bookmark], tags: [Tag]) {
        guard let format = detectFormat(url: url) else {
            throw ImportError.unsupportedFormat
        }
        switch format {
        case .json: return try importJSON(url: url)
        case .csv:  return (try importCSV(url: url), [])
        case .html: return (try importHTML(url: url), [])
        }
    }

    // MARK: - JSON (re-import our own export format)

    private func importJSON(url: URL) throws -> (bookmarks: [Bookmark], tags: [Tag]) {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try full export payload first
        if let payload = try? decoder.decode(ExportPayload.self, from: data) {
            return (payload.bookmarks, payload.tags)
        }
        // Fall back to bare array
        if let bookmarks = try? decoder.decode([Bookmark].self, from: data) {
            return (bookmarks, [])
        }
        throw ImportError.parseError("Could not decode JSON file.")
    }

    // MARK: - CSV

    private func importCSV(url: URL) throws -> [Bookmark] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        // Skip header row if present
        let header = lines[0].lowercased()
        if header.contains("title") && header.contains("url") {
            lines.removeFirst()
        }

        let df = ISO8601DateFormatter()
        var bookmarks: [Bookmark] = []

        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count >= 2 else { continue }
            let url = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }

            let title   = cols.count > 0 ? cols[0] : ""
            let tagList = cols.count > 2 ? cols[2].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : []
            let notes   = cols.count > 3 ? cols[3] : ""
            let dateStr = cols.count > 4 ? cols[4] : ""
            let clicks  = cols.count > 5 ? (Int(cols[5]) ?? 0) : 0
            let date    = df.date(from: dateStr) ?? Date()

            bookmarks.append(Bookmark(title: title, url: url, tags: tagList, notes: notes,
                                       dateAdded: date, clickCount: clicks))
        }
        return bookmarks
    }

    // MARK: - HTML (Netscape Bookmark Format)

    private func importHTML(url: URL) throws -> [Bookmark] {
        let html = try String(contentsOf: url, encoding: .utf8)
        var bookmarks: [Bookmark] = []
        var currentTag: String? = nil

        let lines = html.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()

            // Detect folder/group heading
            if trimmed.contains("<h3>") {
                if let tagRange = line.range(of: "<H3>", options: .caseInsensitive),
                   let closeRange = line.range(of: "</H3>", options: .caseInsensitive, range: tagRange.upperBound..<line.endIndex) {
                    currentTag = String(line[tagRange.upperBound..<closeRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            // Detect <A> bookmark tags
            guard trimmed.contains("<a ") || trimmed.contains("<dt><a ") else { continue }

            // Extract href
            guard let hrefStart = line.range(of: "HREF=\"", options: .caseInsensitive),
                  let hrefEnd = line.range(of: "\"", options: .literal, range: hrefStart.upperBound..<line.endIndex) else { continue }
            let urlStr = String(line[hrefStart.upperBound..<hrefEnd.lowerBound])

            // Extract ADD_DATE if present
            var date = Date()
            if let dateStart = line.range(of: "ADD_DATE=\"", options: .caseInsensitive),
               let dateEnd = line.range(of: "\"", options: .literal, range: dateStart.upperBound..<line.endIndex) {
                let ts = String(line[dateStart.upperBound..<dateEnd.lowerBound])
                if let ti = TimeInterval(ts) { date = Date(timeIntervalSince1970: ti) }
            }

            // Extract link text as title
            var title = ""
            if let gtRange = line.range(of: ">", options: .literal, range: hrefEnd.upperBound..<line.endIndex),
               let ltRange = line.range(of: "<", options: .literal, range: gtRange.upperBound..<line.endIndex) {
                title = String(line[gtRange.upperBound..<ltRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }

            let tags = currentTag.map { [$0] } ?? []
            bookmarks.append(Bookmark(title: title, url: urlStr, tags: tags, dateAdded: date))
        }
        return bookmarks
    }

    // MARK: - CSV line parser (handles quoted fields)

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                if inQuotes, line.index(after: i) < line.endIndex, line[line.index(after: i)] == "\"" {
                    current.append("\"")
                    i = line.index(after: i)
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        result.append(current)
        return result
    }
}

enum ImportError: LocalizedError {
    case unsupportedFormat
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported file format. Use JSON, CSV, or HTML."
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
