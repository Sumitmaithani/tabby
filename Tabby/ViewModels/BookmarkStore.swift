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
        dataService.configure(useICloud: false)
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
        guard !isLoadingMetadata else { return }
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

    // MARK: - Import merge

    func merge(imported: [Bookmark], importedTags: [Tag]) {
        let existingURLs = Set(bookmarks.map { $0.url })
        let newBookmarks = imported.filter { !existingURLs.contains($0.url) }
        bookmarks.insert(contentsOf: newBookmarks, at: 0)

        for tag in importedTags where !tags.contains(where: { $0.name == tag.name }) {
            tags.append(tag)
        }
    }

    // MARK: - Restore from backup

    func restore(bookmarks: [Bookmark], tags: [Tag]) {
        self.bookmarks = bookmarks
        self.tags = tags
    }

    // MARK: - iCloud toggle

    func setICloud(_ enabled: Bool) throws {
        dataService.configure(useICloud: enabled)
        if enabled {
            try dataService.migrateToICloud()
        } else {
            try dataService.migrateFromICloud()
        }
        save()
    }

    // MARK: - Helpers

    private func defaultTags() -> [Tag] {
        let names = ["Work", "Personal", "Reading", "Tools", "Reference"]
        return names.enumerated().map { i, name in
            Tag(name: name, colorHex: Tag.palette[i % Tag.palette.count])
        }
    }
}
