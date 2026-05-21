import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImportCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case needsPermission
        case scanningBrowsers
        case browserChoices([BrowserScanResult])
        case detecting(filename: String)
        case preview(ParsedImport, duplicateCount: Int, showReimportWarning: Bool)
        case importing(total: Int)
        case success(ImportResult)
        case partial(ImportResult)
        case error(ImportErrorKind)
        case formatHelp
    }

    @Published var phase: Phase = .idle
    @Published var progress: (done: Int, total: Int)?
    @Published var lastResult: ImportResult?
    @Published var showLargeFileWarning = false

    private let store: BookmarkStore
    private let settingsStore: SettingsStore
    private var workTask: Task<Void, Never>?
    private var snapshot: (bookmarks: [Bookmark], tags: [Tag])?
    private var pendingParsed: ParsedImport?
    private var pendingPlan: ImportPlan?
    private var lastBrowserScanResults: [BrowserScanResult] = []
    private var pendingBrowserImportSources: [BrowserSource]?

    init(store: BookmarkStore, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    // MARK: - Browser import

    func startBrowserFlow() {
        showLargeFileWarning = false
        if FullDiskAccessChecker.isGranted() {
            scanBrowsers()
        } else {
            phase = .needsPermission
        }
    }

    func resumeBrowserFlowAfterPermission() {
        if FullDiskAccessChecker.isGranted() {
            scanBrowsers()
        } else {
            phase = .needsPermission
        }
    }

    func openPermissionSettings() {
        FullDiskAccessChecker.markResumeAfterGrant()
        FullDiskAccessChecker.openSystemSettings()
    }

    func relaunchAfterPermissionGrant() {
        FullDiskAccessChecker.requestRelaunch()
    }

    func scanBrowsers() {
        phase = .scanningBrowsers
        workTask?.cancel()
        workTask = Task {
            let results = await BrowserBookmarkScanner.shared.scanAll()
            guard !Task.isCancelled else { return }
            lastBrowserScanResults = results
            phase = .browserChoices(results)
        }
    }

    func importBrowsers(selected sources: [BrowserSource]) {
        let results = lastBrowserScanResults.filter { sources.contains($0.source) }
        let parsedList = results.compactMap(\.parsed)
        guard !parsedList.isEmpty else { return }

        pendingBrowserImportSources = sources
        let merged = mergeBrowserParsed(parsedList, sources: sources)
        let plan = buildPlan(
            from: merged,
            importAllFolders: true,
            selectedFolders: [],
            renamedTags: [:]
        )
        commit(plan: plan)
    }

    func selectedBookmarkCount(from results: [BrowserScanResult], selected: Set<BrowserSource>) -> Int {
        results
            .filter { selected.contains($0.source) && $0.isInstalled && !$0.isLocked }
            .reduce(0) { $0 + $1.bookmarkCount }
    }

    func hasAnyInstalledBrowser(in results: [BrowserScanResult]) -> Bool {
        results.contains { $0.isInstalled && ($0.bookmarkCount > 0 || $0.isLocked) }
    }

    private func mergeBrowserParsed(_ list: [ParsedImport], sources: [BrowserSource]) -> ParsedImport {
        var bookmarks: [Bookmark] = []
        var folderCounts: [String: Int] = [:]
        var failedRows: [FailedRow] = []
        var totalBytes = 0
        var seenURLs = Set<String>()
        let service = ImportService.shared

        for parsed in list {
            totalBytes += parsed.totalBytes
            failedRows.append(contentsOf: parsed.failedRows)
            for bookmark in parsed.bookmarks {
                let norm = service.normalizeURL(bookmark.url)
                guard !seenURLs.contains(norm) else { continue }
                seenURLs.insert(norm)
                bookmarks.append(bookmark)
            }
            for (tag, count) in parsed.detectedFolders {
                folderCounts[tag, default: 0] += count
            }
        }

        let names = sources.map(\.displayName).joined(separator: ", ")
        return ParsedImport(
            format: .json,
            bookmarks: bookmarks,
            detectedFolders: folderCounts,
            failedRows: failedRows,
            sourceFilename: names.isEmpty ? "Browser bookmarks" : names,
            sourceHash: nil,
            totalBytes: totalBytes
        )
    }

    private func recordBrowserImportSuccess(sources: [BrowserSource]) {
        settingsStore.settings.lastBrowserImportDate = Date()
        settingsStore.settings.lastBrowserImportSources = sources.map(\.displayName)
        settingsStore.settings.hasCompletedFirstRunImport = true
    }

    // MARK: - File ingest

    func ingest(_ url: URL) {
        guard case .idle = phase else { return }

        let filename = url.lastPathComponent
        phase = .detecting(filename: filename)

        workTask?.cancel()
        workTask = Task {
            do {
                let format = try ImportService.shared.detectFormat(url: url)
                let parsed = try await ImportService.shared.parse(url: url, format: format)

                guard !Task.isCancelled else { return }

                if parsed.bookmarkCount >= Constants.softWarnImportCount {
                    showLargeFileWarning = true
                }

                let duplicateCount = countDuplicates(in: parsed)
                let showReimport = checkReimportWarning(hash: parsed.sourceHash)

                pendingParsed = parsed
                phase = .preview(parsed, duplicateCount: duplicateCount, showReimportWarning: showReimport)
            } catch let error as ImportErrorKind {
                guard !Task.isCancelled else { return }
                phase = .error(mapError(error, filename: filename))
            } catch {
                guard !Task.isCancelled else { return }
                if (error as NSError).domain == NSCocoaErrorDomain,
                   (error as NSError).code == NSFileReadNoPermissionError {
                    phase = .error(.permissionDenied)
                } else {
                    phase = .error(.unknown(filename: filename, detail: error.localizedDescription))
                }
            }
        }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .json, .commaSeparatedText, .html, .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "htm") ?? .html
        ]
        panel.message = "Choose a bookmark file to import"
        if panel.runModal() == .OK, let url = panel.url {
            workTask?.cancel()
            pendingBrowserImportSources = nil
            phase = .idle
            ingest(url)
        }
    }

    // MARK: - Preview → commit

    func buildPlan(
        from parsed: ParsedImport,
        importAllFolders: Bool,
        selectedFolders: Set<String>,
        renamedTags: [String: String]
    ) -> ImportPlan {
        ImportPlan(
            parsed: parsed,
            selectedFolders: importAllFolders ? nil : selectedFolders,
            renamedTags: renamedTags,
            policy: settingsStore.settings.duplicatePolicy
        )
    }

    func commit(plan: ImportPlan) {
        pendingPlan = plan
        let total = planToImportCount(plan: plan)

        if total <= Constants.largeImportThreshold {
            runCommit(plan: plan, showProgress: false)
        } else {
            phase = .importing(total: total)
            runCommit(plan: plan, showProgress: true)
        }
    }

    private func runCommit(plan: ImportPlan, showProgress: Bool) {
        workTask?.cancel()
        workTask = Task {
            snapshot = store.snapshot()

            // MARK: - Opt-A lock file
            writeLockFile(plan: plan)

            if settingsStore.settings.autoBackupBeforeImport {
                BackupService.shared.backup(bookmarks: store.bookmarks, tags: store.tags)
            }

            let total = planToImportCount(plan: plan)
            if showProgress {
                progress = (0, total)
            }

            do {
                let result = try await commitInBatches(plan: plan, total: total)
                guard !Task.isCancelled else {
                    rollback()
                    return
                }

                guard store.persistImmediately() else {
                    rollback()
                    phase = .error(.diskFull)
                    return
                }

                removeLockFile()
                recordImportHistory(parsed: plan.parsed)
                if let browserSources = pendingBrowserImportSources {
                    recordBrowserImportSuccess(sources: browserSources)
                    pendingBrowserImportSources = nil
                }
                lastResult = result

                if result.failedRows.isEmpty {
                    phase = .success(result)
                } else {
                    phase = .partial(result)
                }

                if settingsStore.settings.fetchFavicons, result.imported > 0 {
                    store.fetchMissingFaviconsInBackground()
                }
            } catch is CancellationError {
                rollback()
            } catch {
                rollback()
                phase = .error(.unknown(filename: plan.parsed.sourceFilename, detail: error.localizedDescription))
            }

            progress = nil
            snapshot = nil
        }
    }

    private func commitInBatches(plan: ImportPlan, total: Int) async throws -> ImportResult {
        // Apply all at once in memory (batched yields for UI responsiveness)
        var done = 0
        let batch = Constants.importBatchSize

        while done < total {
            try Task.checkCancellation()
            done = min(done + batch, total)
            if let current = self.progress {
                self.progress = (done, current.total)
            }
            await Task.yield()
        }

        var result = store.apply(plan: plan)
        if settingsStore.settings.autoBackupBeforeImport {
            let backups = BackupService.shared.listBackups()
            result = ImportResult(
                imported: result.imported,
                updated: result.updated,
                tagsCreated: result.tagsCreated,
                duplicatesSkipped: result.duplicatesSkipped,
                failedRows: result.failedRows,
                backupURL: backups.first?.url
            )
        }
        return result
    }

    // MARK: - Cancel / dismiss

    func cancel() {
        workTask?.cancel()
        workTask = nil

        switch phase {
        case .scanningBrowsers:
            progress = nil
            if !lastBrowserScanResults.isEmpty {
                phase = .browserChoices(lastBrowserScanResults)
            } else {
                phase = .idle
            }
            return
        case .importing:
            rollback()
            removeLockFile()
            pendingBrowserImportSources = nil
            if !lastBrowserScanResults.isEmpty {
                phase = .browserChoices(lastBrowserScanResults)
            } else {
                phase = .idle
            }
            progress = nil
            pendingParsed = nil
            pendingPlan = nil
            return
        default:
            break
        }

        rollback()
        removeLockFile()
        progress = nil
        pendingParsed = nil
        pendingPlan = nil
        pendingBrowserImportSources = nil
        phase = .idle
    }

    func dismiss() {
        workTask?.cancel()
        workTask = nil
        progress = nil
        pendingParsed = nil
        pendingPlan = nil
        pendingBrowserImportSources = nil
        phase = .idle
    }

    func skipBrowserOnboarding() {
        settingsStore.settings.hasSkippedImportOnboarding = true
        dismiss()
    }

    func showFormatHelp() {
        phase = .formatHelp
    }

    func backFromFormatHelp() {
        if let parsed = pendingParsed {
            let duplicateCount = countDuplicates(in: parsed)
            let showReimport = checkReimportWarning(hash: parsed.sourceHash)
            phase = .preview(parsed, duplicateCount: duplicateCount, showReimportWarning: showReimport)
        } else {
            phase = .idle
        }
    }

    func retry() {
        phase = .idle
    }

    // MARK: - Duplicate preview count

    func countDuplicates(in parsed: ParsedImport) -> Int {
        let service = ImportService.shared
        let existing = Set(store.bookmarks.map { service.normalizeURL($0.url) })
        return parsed.bookmarks.filter { existing.contains(service.normalizeURL($0.url)) }.count
    }

    func importableCount(parsed: ParsedImport, duplicateCount: Int, selectedFolders: Set<String>?, importAll: Bool) -> Int {
        var list = parsed.bookmarks
        if !importAll, let selected = selectedFolders {
            list = list.filter { selected.contains($0.tags.first ?? "") }
        }
        let policy = settingsStore.settings.duplicatePolicy
        if policy == .skip {
            return list.count - list.filter { bookmark in
                let norm = ImportService.shared.normalizeURL(bookmark.url)
                return store.bookmarks.contains { ImportService.shared.normalizeURL($0.url) == norm }
            }.count
        }
        return list.count
    }

    private func planToImportCount(plan: ImportPlan) -> Int {
        var list = plan.parsed.bookmarks
        if let selected = plan.selectedFolders {
            list = list.filter { selected.contains($0.tags.first ?? "") }
        }
        if plan.policy == .skip {
            let existing = Set(store.bookmarks.map { ImportService.shared.normalizeURL($0.url) })
            return list.filter { !existing.contains(ImportService.shared.normalizeURL($0.url)) }.count
        }
        return list.count
    }

    private func rollback() {
        if let snap = snapshot {
            store.restore(bookmarks: snap.bookmarks, tags: snap.tags)
        }
        removeLockFile()
    }

    private func mapError(_ error: ImportErrorKind, filename: String) -> ImportErrorKind {
        switch error {
        case .unknown(_, let detail):
            return .unknown(filename: filename, detail: detail)
        default:
            return error
        }
    }

    // MARK: - Opt-A lock file

    private func writeLockFile(plan: ImportPlan) {
        let payload = ImportLockPayload(
            filename: plan.parsed.sourceFilename,
            startedAt: Date(),
            bookmarkCount: plan.parsed.bookmarkCount
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: Constants.Paths.importLockFile, options: .atomicWrite)
    }

    private func removeLockFile() {
        try? FileManager.default.removeItem(at: Constants.Paths.importLockFile)
    }

    static func checkCrashRecoveryLock() -> ImportLockPayload? {
        let url = Constants.Paths.importLockFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ImportLockPayload.self, from: data) else {
            return nil
        }
        return payload
    }

    static func discardCrashRecoveryLock() {
        try? FileManager.default.removeItem(at: Constants.Paths.importLockFile)
    }

    // MARK: - Opt-B re-import history

    private func checkReimportWarning(hash: String?) -> Bool {
        guard let hash else { return false }
        let entries = loadImportHistory()
        return entries.contains { $0.hash == hash }
    }

    private func recordImportHistory(parsed: ParsedImport) {
        guard let hash = parsed.sourceHash else { return }
        var entries = loadImportHistory()
        entries.removeAll { $0.hash == hash }
        entries.insert(ImportHistoryEntry(
            hash: hash,
            filename: parsed.sourceFilename,
            byteCount: parsed.totalBytes,
            date: Date()
        ), at: 0)
        entries = Array(entries.prefix(50))
        let file = ImportHistoryFile(entries: entries)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Constants.Paths.importHistoryFile, options: .atomicWrite)
        }
    }

    private func loadImportHistory() -> [ImportHistoryEntry] {
        let url = Constants.Paths.importHistoryFile
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ImportHistoryFile.self, from: data) else {
            return []
        }
        return file.entries
    }
}
