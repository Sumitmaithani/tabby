import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportFlowView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    @EnvironmentObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch coordinator.phase {
            case .idle:
                OnboardingHeroView()
            case .needsPermission:
                BrowserPermissionView()
            case .scanningBrowsers:
                BrowserScanningView()
            case .browserChoices(let results):
                BrowserImportChoicesView(results: results)
            case .detecting(let filename):
                DetectingView(filename: filename)
            case .preview(let parsed, let duplicateCount, let showReimport):
                PreviewView(parsed: parsed, duplicateCount: duplicateCount, showReimportWarning: showReimport)
            case .importing:
                ImportingView()
            case .success(let result):
                SuccessView(result: result)
            case .partial(let result):
                PartialSuccessView(result: result)
            case .error(let kind):
                ImportErrorView(kind: kind)
            case .formatHelp:
                FormatHelpSheet()
            }
        }
        .frame(width: 340)
        .padding(20)
    }
}

// MARK: - Onboarding hero

struct OnboardingHeroView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Bring your bookmarks with you")
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Import from Chrome, Arc, Brave, Edge, Comet, or any file export.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Import from browsers") {
                coordinator.startBrowserFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            dropZone

            Button("Import from file…") {
                coordinator.openFilePicker()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button("Skip for now") {
                settingsStore.settings.hasSkippedImportOnboarding = true
                coordinator.dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button("Don't know how to export? See instructions →") {
                coordinator.showFormatHelp()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                          style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .frame(height: 72)
            .overlay {
                Text("or drag a file here")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                coordinator.ingest(url)
            }
        }
        return true
    }
}

// MARK: - Detecting

private struct DetectingView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    let filename: String
    @State private var showCancel = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text("Reading your file…")
                .font(.system(size: 14, weight: .medium))
            Text(filename)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if showCancel {
                Button("Cancel") { coordinator.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showCancel = true
            }
        }
    }
}

// MARK: - Preview

private struct PreviewView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    @EnvironmentObject var store: BookmarkStore

    let parsed: ParsedImport
    let duplicateCount: Int
    let showReimportWarning: Bool

    @State private var importAllFolders = true
    @State private var selectedFolders: Set<String> = []
    @State private var renamedTags: [String: String] = [:]
    @State private var showFolderPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showReimportWarning {
                Label("You imported this file before. Duplicates will be skipped.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if coordinator.showLargeFileWarning {
                Label("This may take a moment (\(parsed.bookmarkCount) bookmarks).", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Found \(parsed.bookmarkCount) bookmark\(parsed.bookmarkCount == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))

            if parsed.folderCount > 0 {
                Text("in \(parsed.folderCount) folder\(parsed.folderCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $importAllFolders) {
                Text("Import all").tag(true)
                Text("Pick folders").tag(false)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: importAllFolders) { all in
                if !all {
                    selectedFolders = Set(parsed.detectedFolders.keys)
                    showFolderPicker = true
                }
            }

            if !importAllFolders && showFolderPicker {
                folderChecklist
            }

            if duplicateCount > 0 {
                Text("Duplicates: \(duplicateCount) already in Tabby → will be skipped")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { coordinator.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                Button("Import \(importableCount)") {
                    let plan = coordinator.buildPlan(
                        from: parsed,
                        importAllFolders: importAllFolders,
                        selectedFolders: selectedFolders,
                        renamedTags: renamedTags
                    )
                    coordinator.commit(plan: plan)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(importableCount == 0)
            }
        }
        .onAppear {
            selectedFolders = Set(parsed.detectedFolders.keys)
            for key in parsed.detectedFolders.keys {
                renamedTags[key] = key
            }
        }
    }

    private var importableCount: Int {
        coordinator.importableCount(
            parsed: parsed,
            duplicateCount: duplicateCount,
            selectedFolders: importAllFolders ? nil : selectedFolders,
            importAll: importAllFolders
        )
    }

    private var folderChecklist: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parsed.detectedFolders.keys.sorted(), id: \.self) { folder in
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedFolders.contains(folder) },
                            set: { on in
                                if on { selectedFolders.insert(folder) }
                                else { selectedFolders.remove(folder) }
                            }
                        )) {
                            Text("\(folder) (\(parsed.detectedFolders[folder] ?? 0))")
                                .font(.system(size: 11))
                        }
                        .toggleStyle(.checkbox)

                        TextField("Tag name", text: Binding(
                            get: { renamedTags[folder] ?? folder },
                            set: { renamedTags[folder] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .frame(maxWidth: 120)
                    }
                }
            }
        }
        .frame(maxHeight: 140)
    }
}

// MARK: - Importing

private struct ImportingView: View {
    @EnvironmentObject var coordinator: ImportCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Text("Importing bookmarks…")
                .font(.system(size: 14, weight: .medium))

            if let p = coordinator.progress {
                ProgressView(value: Double(p.done), total: Double(p.total))
                Text("\(p.done) / \(p.total)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }

            Button("Cancel") { coordinator.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Success

private struct SuccessView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    @EnvironmentObject var store: BookmarkStore
    let result: ImportResult

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Imported \(result.imported) bookmark\(result.imported == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))

            if result.tagsCreated > 0 {
                Text("\(result.tagsCreated) tag\(result.tagsCreated == 1 ? "" : "s") created")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if result.duplicatesSkipped > 0 {
                Text("\(result.duplicatesSkipped) duplicate\(result.duplicatesSkipped == 1 ? "" : "s") skipped")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button("View bookmarks") {
                store.searchText = ""
                store.selectedTag = nil
                coordinator.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.successAutoDismissSeconds * 1_000_000_000))
                if case .success = coordinator.phase {
                    coordinator.dismiss()
                }
            }
        }
    }
}

// MARK: - Partial success

private struct PartialSuccessView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    let result: ImportResult
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)

            Text("Imported \(result.imported) bookmark\(result.imported == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))

            if !result.failedRows.isEmpty {
                Text("\(result.failedRows.count) bookmark\(result.failedRows.count == 1 ? "" : "s") couldn't be read")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button("See details") { showDetails.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))

                if showDetails {
                    failedRowsList
                }

                // MARK: - Opt-C failed-row CSV
                Button("Download CSV") {
                    exportFailedRowsCSV(result.failedRows)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Done") { coordinator.dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var failedRowsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(result.failedRows.prefix(20)) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Line \(row.line): \(row.reason)")
                            .font(.system(size: 10, weight: .medium))
                        Text(row.raw)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxHeight: 100)
    }

    private func exportFailedRowsCSV(_ rows: [FailedRow]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tabby_import_errors.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["line,raw,reason"]
        for row in rows {
            let raw = csvEscape(row.raw)
            let reason = csvEscape(row.reason)
            lines.append("\(row.line),\(raw),\(reason)")
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvEscape(_ s: String) -> String {
        let needs = s.contains(",") || s.contains("\"")
        if needs { return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        return s
    }
}

// MARK: - Error

private struct ImportErrorView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    let kind: ImportErrorKind

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button(primaryButtonTitle) { primaryAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                if showFormatHelp {
                    Button("Format help") { coordinator.showFormatHelp() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if showReport {
                    Button("Report this") { reportError() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .unsupportedFormat: return "We couldn't read this file."
        case .malformed(let format, _): return "This file looks damaged."
        case .emptyFile: return "This file has no bookmarks in it."
        case .fileTooLarge: return "File too large"
        case .permissionDenied: return "Tabby needs permission to read this file."
        case .diskFull: return "Not enough space to save these bookmarks."
        case .unknown: return "Something went wrong."
        }
    }

    private var subtitle: String {
        switch kind {
        case .unsupportedFormat:
            return "Tabby supports HTML, CSV, JSON, Markdown, and TXT files."
        case .malformed(let format, let detail):
            return "We expected a \(format.displayName) file but couldn't parse it.\n\(detail)\nTry re-exporting from your browser."
        case .emptyFile:
            return "Try a different file."
        case .fileTooLarge(let count):
            return "This file has \(count) bookmarks. Please split into smaller files (max \(Constants.hardImportLimit))."
        case .permissionDenied:
            return "Grant access when prompted, or use Choose file…"
        case .diskFull:
            return "Free up some disk space and try again."
        case .unknown(let filename, let detail):
            return "File: \(filename)\nError: \(detail)"
        }
    }

    private var primaryButtonTitle: String {
        switch kind {
        case .emptyFile: return "Try a different file"
        case .permissionDenied: return "Grant access"
        default: return "Try again"
        }
    }

    private var showFormatHelp: Bool {
        switch kind {
        case .unsupportedFormat, .malformed, .emptyFile: return true
        default: return false
        }
    }

    private var showReport: Bool {
        if case .unknown = kind { return true }
        return false
    }

    private func primaryAction() {
        switch kind {
        case .permissionDenied:
            coordinator.openFilePicker()
        default:
            coordinator.retry()
        }
    }

    private func reportError() {
        let subject = "Tabby import error"
        let body: String
        if case .unknown(let filename, let detail) = kind {
            body = "Error type: unknown\nFilename: \(filename)\nDetail: \(detail)"
        } else {
            body = "Error type: \(kind.userFacingLabel)"
        }
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:?subject=\(subject)&body=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Format help

struct FormatHelpSheet: View {
    @EnvironmentObject var coordinator: ImportCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Export bookmarks from your browser")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { coordinator.backFromFormatHelp() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    helpSection("Chrome, Arc, Brave, Edge",
                                "Open chrome://bookmarks → top-right menu → Export bookmarks → save the HTML file.")
                    helpSection("Firefox",
                                "Press Cmd+Shift+O → Import and Backup → Export Bookmarks to HTML.")
                    helpSection("Safari",
                                "File menu → Export → Bookmarks.")
                    helpSection("Notion",
                                "Open the database with your links → top-right menu → Export → format: CSV.")
                    helpSection("Raindrop, Pocket, other apps",
                                "Look for Export in settings. CSV or HTML both work.")
                    Text("Then drag the file into Tabby.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(body).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
