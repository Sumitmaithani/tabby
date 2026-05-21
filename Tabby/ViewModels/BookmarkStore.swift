import Foundation
import Combine
import SwiftUI

enum SortOption: String, CaseIterable, Identifiable {
    case dateAdded    = "Date Added"
    case alphabetical = "Alphabetical"
    case mostVisited  = "Most Visited"
    case byTag        = "By Tag"

    var id: String { rawValue }
}

@MainActor
final class BookmarkStore: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    @Published var tags: [Tag] = []
    @Published var searchText: String = ""
    @Published var selectedTag: String? = nil
    @Published var sortOption: SortOption = .dateAdded
    @Published var isLoadingMetadata = false

    private let dataService = DataService.shared
    private let backupService = BackupService.shared
    private let faviconService = FaviconService.shared
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        setupAutoSave()
    }

    // MARK: - Load / Save

    func load() {
        bookmarks = dataService.loadBookmarks()
        tags = dataService.loadTags()
        if tags.isEmpty { tags = defaultTags() }
    }

    func save() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms debounce
            guard !Task.isCancelled else { return }
            persistImmediately()
        }
    }

    @discardableResult
    func persistImmediately() -> Bool {
        saveTask?.cancel()
        dataService.ensureStorageReady()
        do {
            try dataService.saveBookmarks(bookmarks)
            try dataService.saveTags(tags)
            backupService.backup(bookmarks: bookmarks, tags: tags)
            return true
        } catch {
            NSLog("Tabby: failed to save bookmarks — \(error.localizedDescription)")
            return false
        }
    }

    private func setupAutoSave() {
        Publishers.MergeMany(
            $bookmarks.map { _ in () }.eraseToAnyPublisher(),
            $tags.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst()
        .sink { [weak self] _ in self?.save() }
        .store(in: &cancellables)
    }

    // MARK: - Filtered / Sorted view

    var filteredBookmarks: [Bookmark] {
        var result = bookmarks.filter { !$0.isArchived }

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.displayTitle.lowercased().contains(q) ||
                $0.url.lowercased().contains(q) ||
                $0.notes.lowercased().contains(q) ||
                $0.tags.contains(where: { $0.lowercased().contains(q) })
            }
        }

        switch sortOption {
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .alphabetical:
            result.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .mostVisited:
            result.sort { $0.clickCount > $1.clickCount }
        case .byTag:
            result.sort { ($0.tags.first ?? "").localizedCaseInsensitiveCompare($1.tags.first ?? "") == .orderedAscending }
        }

        return result
    }

    var allTagNames: [String] {
        Array(Set(bookmarks.flatMap { $0.tags })).sorted()
    }

    // MARK: - CRUD

    func addBookmark(_ bookmark: Bookmark) {
        bookmarks.insert(bookmark, at: 0)
    }

    func update(_ bookmark: Bookmark) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[idx] = bookmark
    }

    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    func delete(at offsets: IndexSet, in list: [Bookmark]) {
        let ids = offsets.map { list[$0].id }
        bookmarks.removeAll { ids.contains($0.id) }
    }

    func recordClick(_ bookmark: Bookmark) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[idx].clickCount += 1
    }

    func open(_ bookmark: Bookmark) {
        guard let url = URL(string: bookmark.url) else { return }
        NSWorkspace.shared.open(url)
        recordClick(bookmark)
    }

    // MARK: - Tag management

    func addTag(_ tag: Tag) {
        guard !tags.contains(where: { $0.name == tag.name }) else { return }
        tags.append(tag)
    }

    func deleteTag(named name: String) {
        tags.removeAll { $0.name == name }
        for idx in bookmarks.indices {
            bookmarks[idx].tags.removeAll { $0 == name }
        }
    }

    func tagObject(named name: String) -> Tag? {
        tags.first { $0.name == name }
    }

    // MARK: - Favicon / metadata fetch

    func fetchMetadata(for bookmark: Bookmark, fetchFavicons: Bool) async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        let (title, faviconData) = await faviconService.fetchMetadata(for: bookmark.url)

        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        if let title, bookmarks[idx].title.isEmpty {
            bookmarks[idx].title = title
        }
        if fetchFavicons, let faviconData {
            bookmarks[idx].faviconData = faviconData
        }
    }

    /// Backfills favicons for bookmarks that have none (e.g. after browser import). Globe icon remains as fallback.
    func fetchMissingFaviconsInBackground() {
        let ids = bookmarks.filter { $0.faviconData == nil && !$0.isArchived }.map(\.id)
        guard !ids.isEmpty else { return }

        Task {
            await fetchFavicons(for: ids)
            persistImmediately()
        }
    }

    func fetchFaviconIfNeeded(bookmarkID: UUID) async {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }),
              bookmarks[idx].faviconData == nil else { return }

        if let data = await faviconService.fetchFavicon(for: bookmarks[idx].url),
           let current = bookmarks.firstIndex(where: { $0.id == bookmarkID }) {
            bookmarks[current].faviconData = data
        }
    }

    private func fetchFavicons(for ids: [UUID]) async {
        let concurrency = 6
        var index = 0

        await withTaskGroup(of: Void.self) { group in
            while index < ids.count {
                let slice = ids[index..<min(index + concurrency, ids.count)]
                index += concurrency
                for id in slice {
                    group.addTask { await self.fetchFaviconIfNeeded(bookmarkID: id) }
                }
                await group.waitForAll()
                await Task.yield()
            }
        }
    }

    // MARK: - Import

    func snapshot() -> (bookmarks: [Bookmark], tags: [Tag]) {
        (bookmarks, tags)
    }

    func apply(plan: ImportPlan) -> ImportResult {
        let service = ImportService.shared
        var toImport = plan.parsed.bookmarks

        if let selected = plan.selectedFolders {
            toImport = toImport.filter { bookmark in
                let folderTag = bookmark.tags.first ?? ""
                return selected.contains(folderTag)
            }
        }

        toImport = toImport.map { bookmark in
            var b = bookmark
            if let oldTag = b.tags.first, let newTag = plan.renamedTags[oldTag] {
                b.tags = [newTag]
            }
            if b.title.trimmingCharacters(in: .whitespaces).isEmpty {
                b.title = service.hostnameTitle(for: b.url)
            }
            return b
        }

        var existingByNormalized: [String: Int] = [:]
        for (idx, b) in bookmarks.enumerated() {
            existingByNormalized[service.normalizeURL(b.url)] = idx
        }

        var imported = 0
        var updated = 0
        var duplicatesSkipped = 0
        var tagsCreated = 0
        var newTagNames = Set<String>()

        for bookmark in toImport {
            let normalized = service.normalizeURL(bookmark.url)
            if let existingIdx = existingByNormalized[normalized] {
                switch plan.policy {
                case .skip:
                    duplicatesSkipped += 1
                case .updateTitle:
                    if !bookmark.title.isEmpty {
                        bookmarks[existingIdx].title = bookmark.title
                    }
                    if !bookmark.tags.isEmpty {
                        bookmarks[existingIdx].tags = bookmark.tags
                    }
                    updated += 1
                case .keepBoth:
                    bookmarks.insert(bookmark, at: 0)
                    imported += 1
                }
            } else {
                bookmarks.insert(bookmark, at: 0)
                existingByNormalized[normalized] = 0
                imported += 1
            }

            for tagName in bookmark.tags where !tagName.isEmpty {
                newTagNames.insert(tagName)
            }
        }

        for tagName in newTagNames {
            if !tags.contains(where: { $0.name == tagName }) {
                let color = Tag.palette[tags.count % Tag.palette.count]
                tags.append(Tag(name: tagName, colorHex: color))
                tagsCreated += 1
            }
        }

        return ImportResult(
            imported: imported,
            updated: updated,
            tagsCreated: tagsCreated,
            duplicatesSkipped: duplicatesSkipped,
            failedRows: plan.parsed.failedRows,
            backupURL: nil
        )
    }

    // MARK: - Restore from backup

    func restore(bookmarks: [Bookmark], tags: [Tag]) {
        self.bookmarks = bookmarks
        self.tags = tags
    }

    // MARK: - Legacy browser tag migration (one-shot)

    /// Collapses `bookmarks-bar.bookmarks-bar.favorites` → `favorites` for bookmarks imported before leaf-only tagging.
    func migrateLegacyBrowserTagsIfNeeded(settingsStore: SettingsStore) {
        guard !settingsStore.settings.hasMigratedBrowserTagsToLeaf else { return }

        let needsMigration = bookmarks.contains { bookmark in
            bookmark.tags.contains { $0.contains(".") || BrowserImportTagging.legacyRootSegments.contains($0) }
        }
        guard needsMigration else {
            settingsStore.settings.hasMigratedBrowserTagsToLeaf = true
            return
        }

        backupService.backup(bookmarks: bookmarks, tags: tags)

        var colorByName: [String: String] = [:]
        for tag in tags {
            colorByName[tag.name] = tag.colorHex
        }

        for idx in bookmarks.indices {
            var newTags: [String] = []
            for oldTag in bookmarks[idx].tags {
                guard let leaf = BrowserImportTagging.migrateLegacyTag(oldTag) else { continue }
                if !newTags.contains(leaf) {
                    newTags.append(leaf)
                }
            }
            bookmarks[idx].tags = newTags
        }

        let referenced = Set(bookmarks.flatMap(\.tags))
        var rebuilt: [Tag] = []
        for name in referenced.sorted() {
            let hex = colorByName[name] ?? Tag.palette[rebuilt.count % Tag.palette.count]
            rebuilt.append(Tag(name: name, colorHex: hex))
        }
        tags = rebuilt.isEmpty ? defaultTags() : rebuilt

        settingsStore.settings.hasMigratedBrowserTagsToLeaf = true
        persistImmediately()
    }

    // MARK: - Helpers

    private func defaultTags() -> [Tag] {
        let names = ["Work", "Personal", "Reading", "Tools", "Reference"]
        return names.enumerated().map { i, name in
            Tag(name: name, colorHex: Tag.palette[i % Tag.palette.count])
        }
    }
}
