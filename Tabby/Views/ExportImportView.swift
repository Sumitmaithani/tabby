import SwiftUI
import UniformTypeIdentifiers

struct ExportImportView: View {
    @EnvironmentObject var store: BookmarkStore
    @State private var exportError: String? = nil
    @State private var importError: String? = nil
    @State private var successMessage: String? = nil
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var selectedFormat: ExportService.ExportFormat = .json

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Export section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Export Bookmarks", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportService.ExportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)

                    Text(formatDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button("Export…") { runExport() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(store.bookmarks.isEmpty)
                }
                .padding(4)
            }

            // Import section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Import Bookmarks", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Supported: JSON (Tabby), CSV, HTML (Netscape bookmarks from Chrome/Firefox/Safari). Duplicate URLs are skipped.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button("Import…") { isImporting = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(4)
            }

            // Feedback
            if let msg = successMessage {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
            if let err = exportError ?? importError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(16)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .commaSeparatedText, .html],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
    }

    // MARK: - Helpers

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

    private func handleImport(result: Result<[URL], Error>) {
        importError = nil
        successMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let (bookmarks, tags) = try ImportService.shared.importBookmarks(from: url)
                store.merge(imported: bookmarks, importedTags: tags)
                successMessage = "Imported \(bookmarks.count) bookmarks."
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
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
