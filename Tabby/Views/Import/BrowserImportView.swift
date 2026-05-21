import SwiftUI

// MARK: - Permission (PRD §7.1 Step 1)

struct BrowserPermissionView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    var showSkip: Bool = true
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Tabby")
                .font(.system(size: 15, weight: .semibold))

            Text("To import your bookmarks, Tabby needs permission to read browser files on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Grant access") {
                coordinator.openPermissionSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button("I've enabled access — restart Tabby") {
                coordinator.relaunchAfterPermissionGrant()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if showSkip {
                Button("Skip — I'll add manually") {
                    if let onSkip { onSkip() }
                    else { coordinator.skipBrowserOnboarding() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Text("Tabby only reads bookmark files from Chrome, Arc, Brave, Edge, and Comet. Nothing leaves your Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Scanning

struct BrowserScanningView: View {
    @EnvironmentObject var coordinator: ImportCoordinator

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Scanning browsers…")
                .font(.system(size: 14, weight: .medium))
            Button("Cancel") { coordinator.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Detection list (PRD §7.1 Step 2)

struct BrowserImportChoicesView: View {
    @EnvironmentObject var coordinator: ImportCoordinator

    let results: [BrowserScanResult]
    var compactFooter: Bool = false

    @State private var selected: Set<BrowserSource> = []

    private var orderedSources: [BrowserSource] {
        BrowserSource.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if coordinator.hasAnyInstalledBrowser(in: results) {
                installedContent
            } else {
                emptyContent
            }
        }
        .onAppear { syncSelection(from: results) }
        .onChange(of: results.map(\.id)) { _ in syncSelection(from: results) }
    }

    private var installedContent: some View {
        Group {
            Text("Found bookmarks to import")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(orderedSources, id: \.self) { source in
                    if let row = results.first(where: { $0.source == source }) {
                        browserRow(row)
                    }
                }
            }
            .padding(.horizontal, 12)

            if let locked = results.first(where: { $0.isLocked }) {
                Label(
                    "\(locked.source.displayName) is running. Quit \(locked.source.displayName) and try again, or import from file.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            }

            Text("Tabby imports from your default browser profile. Multi-profile support coming soon.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack {
                if !compactFooter {
                    Button("Cancel") { coordinator.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                Button(importButtonTitle) {
                    coordinator.importBrowsers(selected: Array(selected))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedImportCount == 0)
            }

            Button("Or import from file →") {
                coordinator.openFilePicker()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Text("No supported browsers found")
                .font(.system(size: 14, weight: .semibold))

            Text("Tabby works with Chrome, Arc, Brave, Edge, and Comet.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Or import from file →") {
                coordinator.openFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if !compactFooter {
                Button("Cancel") { coordinator.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func browserRow(_ row: BrowserScanResult) -> some View {
        let enabled = row.isInstalled && !row.isLocked && row.bookmarkCount > 0

        HStack(spacing: 10) {
            if row.isInstalled && enabled {
                Toggle(isOn: Binding(
                    get: { selected.contains(row.source) },
                    set: { on in
                        if on { selected.insert(row.source) }
                        else { selected.remove(row.source) }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                Image(systemName: row.isInstalled ? "minus.circle" : "circle")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }

            Image(row.source.iconAssetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(row.source.displayName)
                .font(.system(size: 12, weight: enabled ? .medium : .regular))
                .foregroundStyle(enabled ? .primary : .tertiary)

            Spacer()

            Text(rowStatusText(row))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .opacity(row.isInstalled ? 1 : 0.55)
    }

    private func rowStatusText(_ row: BrowserScanResult) -> String {
        if !row.isInstalled { return "not installed" }
        if row.isLocked { return "file locked" }
        if row.bookmarkCount > 0 { return "\(row.bookmarkCount) bookmarks" }
        if row.error != nil { return "unreadable" }
        return "0 bookmarks"
    }

    private var selectedImportCount: Int {
        coordinator.selectedBookmarkCount(from: results, selected: selected)
    }

    private var importButtonTitle: String {
        let n = selectedImportCount
        if n == 0 { return "Import" }
        return "Import \(n)"
    }

    private func syncSelection(from results: [BrowserScanResult]) {
        selected = Set(
            results
                .filter { $0.isInstalled && !$0.isLocked && $0.bookmarkCount > 0 }
                .map(\.source)
        )
    }
}
