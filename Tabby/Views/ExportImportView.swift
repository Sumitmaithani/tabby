import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportImportView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var importCoordinator: ImportCoordinator

    @Binding var showImportSheet: Bool
    var onViewBackups: (() -> Void)?

    @State private var exportError: String? = nil
    @State private var successMessage: String? = nil
    @State private var selectedFormat: ExportService.ExportFormat = .json

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            sectionHeader("Data")

            Button {
                importCoordinator.startBrowserFlow()
                showImportSheet = true
            } label: {
                Label("Import from browsers", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(importCoordinator.isActive)

            Button {
                importCoordinator.phase = .idle
                showImportSheet = true
                importCoordinator.openFilePicker()
            } label: {
                Label("Import from file", systemImage: "doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(importCoordinator.isActive)

            if let lastDate = settingsStore.settings.lastBrowserImportDate {
                Text(lastImportedCaption(date: lastDate, sources: settingsStore.settings.lastBrowserImportSources))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            sectionHeader("Export")

            Picker("Format", selection: $selectedFormat) {
                ForEach(ExportService.ExportFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            Text(formatDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("Export…") { runExport() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.bookmarks.isEmpty)

            Divider()

            sectionHeader("Import options")

            Picker("On duplicate import", selection: $settingsStore.settings.duplicatePolicy) {
                ForEach(DuplicatePolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.menu)

            Toggle("Auto-backup before import", isOn: $settingsStore.settings.autoBackupBeforeImport)

            Button("View backups") {
                onViewBackups?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let msg = successMessage {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
            if let err = exportError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    private func lastImportedCaption(date: Date, sources: [String]) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        if sources.isEmpty {
            return "Last imported \(relative)"
        }
        return "Last imported \(relative) from \(sources.joined(separator: ", "))"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }

    private var formatDescription: String {
        switch selectedFormat {
        case .csv:      return "Spreadsheet-compatible. Columns: Title, URL, Tags, Notes, Date, Click Count."
        case .json:     return "Full data export. Can be re-imported into Tabby."
        case .pdf:      return "Printable PDF with clickable links, grouped by tag."
        case .html:     return "Netscape format. Import directly into Chrome, Firefox, or Safari."
        case .markdown: return "Markdown list grouped by tag. Great for notes apps."
        }
    }

    private func runExport() {
        exportError = nil
        successMessage = nil
        let ext = selectedFormat.fileExtension
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType(for: selectedFormat)]
        panel.nameFieldStringValue = "tabby_export.\(ext)"
        panel.title = "Export Bookmarks"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ExportService.shared.export(
                bookmarks: store.bookmarks,
                tags: store.tags,
                format: selectedFormat,
                to: url
            )
            successMessage = "Exported \(store.bookmarks.count) bookmarks."
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func contentType(for format: ExportService.ExportFormat) -> UTType {
        switch format {
        case .csv:      return .commaSeparatedText
        case .json:     return .json
        case .pdf:      return .pdf
        case .html:     return .html
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}
