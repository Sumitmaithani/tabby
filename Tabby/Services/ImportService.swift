import Foundation
import CryptoKit

final class ImportService {
    static let shared = ImportService()
    private init() {}

    // MARK: - Detection

    func detectFormat(url: URL) throws -> ImportFormat {
        let ext = url.pathExtension.lowercased()
        if let byExt = ImportFormat.allCases.first(where: { $0.expectedExtensions.contains(ext) }) {
            return byExt
        }

        let sample = try readSample(from: url, maxBytes: 4096)
        if let sniffed = sniffFormat(sample: sample, filename: url.lastPathComponent) {
            return sniffed
        }

        throw ImportErrorKind.unsupportedFormat
    }

    private func sniffFormat(sample: String, filename: String) -> ImportFormat? {
        let upper = sample.uppercased()
        if upper.contains("<DT><A HREF=") || upper.contains("<A HREF=") {
            return .html
        }

        let firstLine = sample.components(separatedBy: .newlines).first?.lowercased() ?? ""
        if firstLine.contains("url") || firstLine.contains("link") || firstLine.contains("href") {
            if firstLine.contains(",") { return .csv }
        }

        if let data = sample.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if json is [Any] { return .json }
            if let dict = json as? [String: Any], dict["bookmarks"] != nil { return .json }
        }

        let mdLink = #"\[([^\]]+)\]\(([^)]+)\)"#
        if sample.range(of: mdLink, options: .regularExpression) != nil { return .md }

        let lines = sample.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !lines.isEmpty, lines.allSatisfy({ line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return repairURL(trimmed) != nil
        }) {
            return .txt
        }

        _ = filename
        return nil
    }

    // MARK: - Parse

    func parse(url: URL, format: ImportFormat) async throws -> ParsedImport {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attrs[.size] as? Int) ?? 0
        let hash = sha256(of: url)
        let filename = url.lastPathComponent

        let content: String
        if byteCount > Constants.streamThresholdBytes {
            content = try readFullFileStreaming(url: url)
        } else {
            content = try String(contentsOf: url, encoding: .utf8)
        }

        var failedRows: [FailedRow] = []
        var bookmarks: [Bookmark] = []
        var folderCounts: [String: Int] = [:]

        switch format {
        case .html:
            let (parsed, folders) = try parseHTML(content)
            bookmarks = parsed
            folderCounts = folders
        case .csv:
            let result = try parseCSV(content)
            bookmarks = result.bookmarks
            failedRows = result.failed
        case .json:
            bookmarks = try parseJSON(content)
        case .md:
            let result = parseMarkdown(content)
            bookmarks = result.bookmarks
            failedRows = result.failed
        case .txt:
            let result = parseTXT(content)
            bookmarks = result.bookmarks
            failedRows = result.failed
        }

        if bookmarks.count > Constants.hardImportLimit {
            throw ImportErrorKind.fileTooLarge(count: bookmarks.count)
        }

        if bookmarks.isEmpty && failedRows.isEmpty {
            throw ImportErrorKind.emptyFile
        }

        return ParsedImport(
            format: format,
            bookmarks: bookmarks,
            detectedFolders: folderCounts,
            failedRows: failedRows,
            sourceFilename: filename,
            sourceHash: hash,
            totalBytes: byteCount
        )
    }

    // MARK: - URL helpers

    func normalizeURL(_ raw: String) -> String {
        guard let repaired = repairURL(raw),
              var components = URLComponents(string: repaired) else {
            return raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let scheme = components.scheme {
            components.scheme = scheme.lowercased()
        }
        if let host = components.host {
            components.host = host.lowercased()
        }

        var path = components.path
        while path.hasSuffix("/"), path.count > 1 {
            path.removeLast()
        }
        components.path = path

        if var items = components.queryItems, !items.isEmpty {
            items.removeAll { item in
                let name = item.name.lowercased()
                return name.hasPrefix("utm_") || name == "fbclid" || name == "gclid"
            }
            components.queryItems = items.isEmpty ? nil : items
        }

        return components.string ?? repaired
    }

    func repairURL(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return trimmed
    }

    func hostnameTitle(for urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - HTML

    private func parseHTML(_ html: String) throws -> ([Bookmark], [String: Int]) {
        let lines = html.components(separatedBy: .newlines)
        var root = FolderNode(path: [])
        var stack: [FolderNode] = [root]
        var currentPath: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.contains("<h3") {
                if let name = extractTagContent(from: line, tag: "H3") {
                    currentPath.append(name)
                    let node = FolderNode(path: currentPath)
                    if !stack.isEmpty {
                        stack[stack.count - 1].children.append(node)
                    }
                    stack.append(node)
                }
                continue
            }

            if lower.contains("</dl>") {
                if stack.count > 1 {
                    stack.removeLast()
                    if !currentPath.isEmpty { currentPath.removeLast() }
                }
                continue
            }

            guard lower.contains("<a ") || lower.contains("<dt><a ") else { continue }

            guard let urlStr = extractAttribute("HREF", from: line),
                  let repaired = repairURL(urlStr) else { continue }

            var date = Date()
            if let addDate = extractAttribute("ADD_DATE", from: line),
               let ti = TimeInterval(addDate) {
                date = Date(timeIntervalSince1970: ti)
            }

            var title = extractLinkText(from: line) ?? ""
            if title.isEmpty { title = hostnameTitle(for: repaired) }

            let tag = FolderNode.flattenTag(from: currentPath)
            var tags: [String] = []
            if !tag.isEmpty { tags = [tag] }

            let bookmark = Bookmark(title: title, url: repaired, tags: tags, dateAdded: date)
            if !stack.isEmpty {
                stack[stack.count - 1].bookmarks.append(bookmark)
            }
        }

        var allBookmarks: [Bookmark] = []
        var folderCounts: [String: Int] = [:]
        for (bookmark, tag) in root.flattenedBookmarks() {
            allBookmarks.append(bookmark)
            if !tag.isEmpty {
                folderCounts[tag, default: 0] += 1
            }
        }

        if allBookmarks.isEmpty {
            throw ImportErrorKind.malformed(format: .html, detail: "No bookmarks found in HTML.")
        }

        return (allBookmarks, folderCounts)
    }

    // MARK: - CSV

    private struct CSVParseResult {
        let bookmarks: [Bookmark]
        let failed: [FailedRow]
    }

    private func parseCSV(_ raw: String) throws -> CSVParseResult {
        var lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return CSVParseResult(bookmarks: [], failed: []) }

        let headerCols = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        var urlIdx = headerCols.firstIndex(where: { $0 == "url" || $0 == "link" || $0 == "href" })
        var titleIdx = headerCols.firstIndex(where: { $0 == "title" || $0 == "name" })
        var tagsIdx = headerCols.firstIndex(where: { $0 == "tags" || $0 == "tag" || $0 == "folder" })
        var notesIdx = headerCols.firstIndex(where: { $0 == "notes" || $0 == "note" || $0 == "description" })
        var dateIdx = headerCols.firstIndex(where: { $0.contains("date") })
        var clicksIdx = headerCols.firstIndex(where: { $0.contains("click") })

        let hasHeader = urlIdx != nil || (headerCols.contains("title") && headerCols.contains("url"))
        if hasHeader {
            lines.removeFirst()
        } else {
            urlIdx = 1
            titleIdx = 0
            tagsIdx = 2
            notesIdx = 3
            dateIdx = 4
            clicksIdx = 5
        }

        let df = ISO8601DateFormatter()
        var bookmarks: [Bookmark] = []
        var failed: [FailedRow] = []
        var lineNum = hasHeader ? 2 : 1

        for line in lines {
            let cols = parseCSVLine(line)
            let urlCol = urlIdx ?? 1
            guard cols.count > urlCol else {
                failed.append(FailedRow(line: lineNum, raw: line, reason: "Missing URL column"))
                lineNum += 1
                continue
            }

            let urlRaw = cols[urlCol].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let repaired = repairURL(urlRaw) else {
                failed.append(FailedRow(line: lineNum, raw: line, reason: "Invalid URL"))
                lineNum += 1
                continue
            }

            var title = ""
            if let ti = titleIdx, cols.count > ti { title = cols[ti] }
            if title.isEmpty { title = hostnameTitle(for: repaired) }

            var tagList: [String] = []
            if let tgi = tagsIdx, cols.count > tgi {
                tagList = cols[tgi]
                    .components(separatedBy: CharacterSet(charactersIn: ";,"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }

            var notes = ""
            if let ni = notesIdx, cols.count > ni { notes = cols[ni] }

            var date = Date()
            if let di = dateIdx, cols.count > di {
                date = df.date(from: cols[di]) ?? Date()
            }

            var clicks = 0
            if let ci = clicksIdx, cols.count > ci {
                clicks = Int(cols[ci]) ?? 0
            }

            bookmarks.append(Bookmark(title: title, url: repaired, tags: tagList, notes: notes,
                                       dateAdded: date, clickCount: clicks))
            lineNum += 1
        }

        return CSVParseResult(bookmarks: bookmarks, failed: failed)
    }

    // MARK: - JSON

    private func parseJSON(_ content: String) throws -> [Bookmark] {
        guard let data = content.data(using: .utf8) else {
            throw ImportErrorKind.malformed(format: .json, detail: "Invalid UTF-8.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let payload = try? decoder.decode(ExportPayload.self, from: data) {
            return payload.bookmarks
        }
        if let bookmarks = try? decoder.decode([Bookmark].self, from: data) {
            return bookmarks
        }

        struct GenericEntry: Decodable {
            let url: String
            let title: String?
            let tags: [String]?
        }
        if let entries = try? decoder.decode([GenericEntry].self, from: data) {
            return entries.compactMap { entry in
                guard let repaired = repairURL(entry.url) else { return nil }
                let title = entry.title?.isEmpty == false ? entry.title! : hostnameTitle(for: repaired)
                return Bookmark(title: title, url: repaired, tags: entry.tags ?? [])
            }
        }

        throw ImportErrorKind.malformed(format: .json, detail: "Could not decode JSON.")
    }

    // MARK: - Markdown

    private struct LineParseResult {
        let bookmarks: [Bookmark]
        let failed: [FailedRow]
    }

    private func parseMarkdown(_ content: String) -> LineParseResult {
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        let barePattern = #"\bhttps?://\S+"#
        var bookmarks: [Bookmark] = []
        var failed: [FailedRow] = []
        var lineNum = 1
        var seenURLs = Set<String>()

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { lineNum += 1; continue }

            if let regex = try? NSRegularExpression(pattern: linkPattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               match.numberOfRanges >= 3,
               let titleRange = Range(match.range(at: 1), in: trimmed),
               let urlRange = Range(match.range(at: 2), in: trimmed) {
                let title = String(trimmed[titleRange])
                let urlRaw = String(trimmed[urlRange])
                if let repaired = repairURL(urlRaw), !seenURLs.contains(repaired) {
                    seenURLs.insert(repaired)
                    bookmarks.append(Bookmark(title: title, url: repaired))
                }
                lineNum += 1
                continue
            }

            if let regex = try? NSRegularExpression(pattern: barePattern) {
                let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
                for m in matches {
                    if let r = Range(m.range, in: trimmed) {
                        let urlRaw = String(trimmed[r])
                        if let repaired = repairURL(urlRaw), !seenURLs.contains(repaired) {
                            seenURLs.insert(repaired)
                            bookmarks.append(Bookmark(title: hostnameTitle(for: repaired), url: repaired))
                        }
                    }
                }
                if matches.isEmpty {
                    failed.append(FailedRow(line: lineNum, raw: line, reason: "No URL found"))
                }
            }

            lineNum += 1
        }

        return LineParseResult(bookmarks: bookmarks, failed: failed)
    }

    // MARK: - TXT

    private func parseTXT(_ content: String) -> LineParseResult {
        var bookmarks: [Bookmark] = []
        var failed: [FailedRow] = []
        var lineNum = 1

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { lineNum += 1; continue }

            if let repaired = repairURL(trimmed) {
                bookmarks.append(Bookmark(title: hostnameTitle(for: repaired), url: repaired))
            } else {
                failed.append(FailedRow(line: lineNum, raw: line, reason: "Invalid URL"))
            }
            lineNum += 1
        }

        return LineParseResult(bookmarks: bookmarks, failed: failed)
    }

    // MARK: - File IO

    private func readSample(from url: URL, maxBytes: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func readFullFileStreaming(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = ""
        while true {
            let chunk = try handle.read(upToCount: 65536) ?? Data()
            if chunk.isEmpty { break }
            if let piece = String(data: chunk, encoding: .utf8) {
                result += piece
            }
        }
        return result
    }

    // MARK: - HTML helpers

    private func extractAttribute(_ name: String, from line: String) -> String? {
        let pattern = "\(name)=\""
        guard let start = line.range(of: pattern, options: .caseInsensitive),
              let end = line.range(of: "\"", options: .literal, range: start.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[start.upperBound..<end.lowerBound])
    }

    private func extractTagContent(from line: String, tag: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = line.range(of: open, options: .caseInsensitive),
              let end = line.range(of: close, options: .caseInsensitive, range: start.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private func extractLinkText(from line: String) -> String? {
        guard let gt = line.range(of: ">", options: .backwards),
              let lt = line.range(of: "<", options: .literal, range: gt.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[gt.upperBound..<lt.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - CSV line parser

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
