import Foundation

final class BrowserBookmarkScanner {
    static let shared = BrowserBookmarkScanner()
    private let importService = ImportService.shared
    private init() {}

    func scanAll() async -> [BrowserScanResult] {
        await withTaskGroup(of: BrowserScanResult.self) { group in
            for source in BrowserSource.allCases {
                group.addTask { await self.scan(source: source) }
            }
            var results: [BrowserScanResult] = []
            for await result in group {
                results.append(result)
            }
            return BrowserSource.allCases.compactMap { src in
                results.first { $0.source == src }
            }
        }
    }

    func scan(source: BrowserSource) async -> BrowserScanResult {
        guard let path = source.resolvedBookmarksURL() else {
            return .notInstalled(source)
        }

        do {
            let data = try await readBookmarkFile(at: path)
            let parsed = try parse(data: data, source: source)
            return BrowserScanResult(
                source: source,
                isInstalled: true,
                isLocked: false,
                bookmarkCount: parsed.bookmarkCount,
                parsed: parsed,
                error: nil
            )
        } catch ScannerError.locked {
            return BrowserScanResult(
                source: source,
                isInstalled: true,
                isLocked: true,
                bookmarkCount: 0,
                parsed: nil,
                error: .malformed(format: .json, detail: "Browser may be running.")
            )
        } catch {
            return BrowserScanResult(
                source: source,
                isInstalled: true,
                isLocked: false,
                bookmarkCount: 0,
                parsed: nil,
                error: .malformed(format: .json, detail: error.localizedDescription)
            )
        }
    }

    // MARK: - Read with retry

    private enum ScannerError: Error {
        case locked
        case parseFailed(String)
    }

    private func readBookmarkFile(at url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Self.readWithRetry(url: url)
        }.value
    }

    private nonisolated static func readWithRetry(url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            Thread.sleep(forTimeInterval: 0.5)
            do {
                return try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw ScannerError.locked
            }
        }
    }

    // MARK: - Parse dispatch

    private func parse(data: Data, source: BrowserSource) throws -> ParsedImport {
        switch source {
        case .arc:
            return try parseArc(data: data, source: source)
        case .chrome, .brave, .edge, .comet:
            return try parseChromium(data: data, source: source)
        }
    }

    // MARK: - Chromium (Chrome, Brave, Edge, Comet)

    private struct ChromiumBookmarksFile: Decodable {
        let roots: ChromiumRoots?
    }

    private struct ChromiumRoots: Decodable {
        let bookmark_bar: ChromiumNode?
        let other: ChromiumNode?
        let synced: ChromiumNode?
    }

    private struct ChromiumNode: Decodable {
        let type: String?
        let name: String?
        let url: String?
        let date_added: FlexibleInt?
        let children: [ChromiumNode]?
    }

    private struct FlexibleInt: Decodable {
        let value: Int64

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int64.self) {
                value = intVal
            } else if let strVal = try? container.decode(String.self), let parsed = Int64(strVal) {
                value = parsed
            } else {
                value = 0
            }
        }
    }

    private func parseChromium(data: Data, source: BrowserSource) throws -> ParsedImport {
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(ChromiumBookmarksFile.self, from: data),
              let roots = file.roots else {
            throw ScannerError.parseFailed("Invalid Chromium bookmark JSON.")
        }

        var bookmarks: [Bookmark] = []
        var folderCounts: [String: Int] = [:]

        if let bar = roots.bookmark_bar {
            collectChromium(node: bar, path: [], into: &bookmarks, folderCounts: &folderCounts)
        }
        if let other = roots.other {
            collectChromium(node: other, path: [], into: &bookmarks, folderCounts: &folderCounts)
        }
        if let synced = roots.synced {
            collectChromium(node: synced, path: [], into: &bookmarks, folderCounts: &folderCounts)
        }

        if bookmarks.isEmpty {
            throw ScannerError.parseFailed("No bookmarks found.")
        }

        return makeParsedImport(
            bookmarks: bookmarks,
            folderCounts: folderCounts,
            source: source,
            byteCount: data.count
        )
    }

    private func collectChromium(
        node: ChromiumNode,
        path: [String],
        into bookmarks: inout [Bookmark],
        folderCounts: inout [String: Int]
    ) {
        let nodeType = node.type?.lowercased() ?? ""

        if nodeType == "url" {
            guard let urlRaw = node.url,
                  let repaired = importService.repairURL(urlRaw) else { return }

            var title = node.name?.trimmingCharacters(in: .whitespaces) ?? ""
            if title.isEmpty { title = importService.hostnameTitle(for: repaired) }

            var tags: [String] = []
            if let leaf = BrowserImportTagging.leafTag(fromFolderPath: path) {
                tags = [leaf]
            }

            var date = Date()
            if let micros = node.date_added?.value, micros > 0 {
                date = Date(timeIntervalSince1970: TimeInterval(micros) / 1_000_000)
            }

            bookmarks.append(Bookmark(title: title, url: repaired, tags: tags, dateAdded: date))
            if let leaf = tags.first {
                folderCounts[leaf, default: 0] += 1
            }
            return
        }

        if nodeType == "folder" || node.children != nil {
            var childPath = path
            if let name = node.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                let normalized = BrowserImportTagging.normalizeFolderSegment(name)
                let skipRoot = path.isEmpty && BrowserImportTagging.isChromiumSystemRootFolder(name)
                if !skipRoot {
                    childPath.append(normalized)
                }
            }
            for child in node.children ?? [] {
                collectChromium(node: child, path: childPath, into: &bookmarks, folderCounts: &folderCounts)
            }
        }
    }

    // MARK: - Arc (StorableSidebar.json)

    private struct ArcSidebarFile: Decodable {
        let sidebarSyncState: ArcSyncState?
    }

    private struct ArcSyncState: Decodable {
        let items: [ArcItem]?
    }

    private struct ArcItem: Decodable {
        let id: String?
        let parentID: String?
        let title: String?
        let url: String?
        let data: ArcItemData?
    }

    private struct ArcItemData: Decodable {
        let tab: ArcTabData?
    }

    private struct ArcTabData: Decodable {
        let savedURL: String?
        let savedTitle: String?
    }

    private func parseArc(data: Data, source: BrowserSource) throws -> ParsedImport {
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(ArcSidebarFile.self, from: data),
              let items = file.sidebarSyncState?.items, !items.isEmpty else {
            // Fallback: try Chromium format if Arc ever stores Bookmarks-style JSON here.
            if let chromium = try? parseChromium(data: data, source: source), chromium.bookmarkCount > 0 {
                return chromium
            }
            throw ScannerError.parseFailed("Could not read Arc sidebar data.")
        }

        var childrenByParent: [String?: [ArcItem]] = [:]
        var titleByID: [String: String] = [:]

        for item in items {
            let itemID = item.id ?? UUID().uuidString
            if let title = item.title, !title.isEmpty {
                titleByID[itemID] = title
            }
            childrenByParent[item.parentID, default: []].append(item)
        }

        var bookmarks: [Bookmark] = []
        var folderCounts: [String: Int] = [:]

        func walk(parentID: String?, path: [String]) {
            let children = childrenByParent[parentID] ?? []
            for item in children {
                let itemID = item.id ?? UUID().uuidString
                let urlRaw = item.url ?? item.data?.tab?.savedURL
                let name = item.title ?? item.data?.tab?.savedTitle ?? titleByID[itemID]

                if let urlRaw, let repaired = importService.repairURL(urlRaw) {
                    var title = name?.trimmingCharacters(in: .whitespaces) ?? ""
                    if title.isEmpty { title = importService.hostnameTitle(for: repaired) }
                    var tags: [String] = []
                    if let leaf = BrowserImportTagging.leafTag(fromFolderPath: path) {
                        tags = [leaf]
                    }
                    bookmarks.append(Bookmark(title: title, url: repaired, tags: tags))
                    if let leaf = tags.first {
                        folderCounts[leaf, default: 0] += 1
                    }
                } else if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    var childPath = path
                    let segment = BrowserImportTagging.normalizeFolderSegment(name)
                    childPath.append(segment)
                    walk(parentID: itemID, path: childPath)
                } else {
                    walk(parentID: itemID, path: path)
                }
            }
        }

        walk(parentID: nil, path: [])

        if bookmarks.isEmpty {
            throw ScannerError.parseFailed("No bookmarks found in Arc.")
        }

        return makeParsedImport(
            bookmarks: bookmarks,
            folderCounts: folderCounts,
            source: source,
            byteCount: data.count
        )
    }

    private func makeParsedImport(
        bookmarks: [Bookmark],
        folderCounts: [String: Int],
        source: BrowserSource,
        byteCount: Int
    ) -> ParsedImport {
        ParsedImport(
            format: .json,
            bookmarks: bookmarks,
            detectedFolders: folderCounts,
            failedRows: [],
            sourceFilename: "\(source.displayName) bookmarks",
            sourceHash: nil,
            totalBytes: byteCount
        )
    }
}
