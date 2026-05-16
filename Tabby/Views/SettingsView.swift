import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var hotKeyManager: HotKeyManagerWrapper

    var onDismiss: (() -> Void)? = nil

    @State private var selectedTab: SettingsTab = .general
    @State private var iCloudError: String? = nil
    @State private var restoreError: String? = nil
    @State private var restoreSuccess = false

    enum SettingsTab: String, CaseIterable {
        case general  = "General"
        case sync     = "Sync"
        case backup   = "Backup"
        case exportImport = "Export/Import"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onDismiss {
                HStack {
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("Done", action: onDismiss)
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        sidebarButton(tab)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(width: 120)
                .background(.background.opacity(0.4))

                Divider()

                ScrollView {
                    Group {
                        switch selectedTab {
                        case .general:      generalTab
                        case .sync:         syncTab
                        case .backup:       backupTab
                        case .exportImport: ExportImportView()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: Constants.PopoverSize.width - 16, height: Constants.PopoverSize.height - 16)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Behaviour")

            Toggle("Launch at login", isOn: Binding(
                get: { settingsStore.settings.launchAtLogin },
                set: { settingsStore.setLaunchAtLogin($0) }
            ))

            Toggle("Compact view", isOn: $settingsStore.settings.compactView)

            Toggle("Auto-fetch page title & favicon", isOn: $settingsStore.settings.fetchFavicons)
                .help("Fetches the page title and favicon when you paste a URL.")

            Divider()
            sectionHeader("Appearance")

            Picker("Theme", selection: $settingsStore.settings.themeOverride) {
                ForEach(AppSettings.ThemeOverride.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settingsStore.settings.themeOverride) { _ in
                settingsStore.applyTheme()
            }

            Divider()
            sectionHeader("Keyboard Shortcut")

            Text("Global shortcut: ⌘⇧L (Cmd+Shift+L)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("To change the shortcut, edit HotKeyManager.swift and rebuild.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Sync

    private var syncTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("iCloud Drive Sync")

            Toggle("Store data in iCloud Drive", isOn: Binding(
                get: { settingsStore.settings.useICloudSync },
                set: { newValue in
                    iCloudError = nil
                    do {
                        try store.setICloud(newValue)
                        settingsStore.settings.useICloudSync = newValue
                    } catch {
                        iCloudError = error.localizedDescription
                    }
                }
            ))

            Text("When enabled, your bookmarks are stored in iCloud Drive and synced across all your Apple devices running Tabby.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if settingsStore.settings.useICloudSync {
                Label("Syncing via iCloud Drive", systemImage: "icloud.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
            }

            if let err = iCloudError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Text("Data location: \(settingsStore.settings.useICloudSync ? "~/Library/Mobile Documents/…" : "~/Library/Application Support/Tabby/")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }

    // MARK: - Backup

    private var backupTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Auto Backups")
            Text("Tabby keeps the last \(Constants.maxBackups) backups. A backup is created on every save.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()
            sectionHeader("Stored Backups")

            let backups = BackupService.shared.listBackups()
            if backups.isEmpty {
                Text("No backups found.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(backups) { backup in
                    HStack {
                        Image(systemName: "doc.badge.clock")
                            .foregroundStyle(.secondary)
                        Text(backup.displayName)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Restore") {
                            restoreFromBackup(backup)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button(role: .destructive) {
                            try? BackupService.shared.delete(backup: backup)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.7))
                    }
                }
            }

            if restoreSuccess {
                Label("Restored successfully.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            if let err = restoreError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sidebarButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        Button { selectedTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: tabIcon(tab)).frame(width: 16)
                Text(tab.rawValue).font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }

    private func tabIcon(_ tab: SettingsTab) -> String {
        switch tab {
        case .general:      return "gearshape"
        case .sync:         return "arrow.triangle.2.circlepath"
        case .backup:       return "clock.arrow.circlepath"
        case .exportImport: return "square.and.arrow.up.on.square"
        }
    }

    private func restoreFromBackup(_ backup: BackupInfo) {
        restoreError = nil
        restoreSuccess = false
        do {
            let (bookmarks, tags) = try BackupService.shared.restore(from: backup.url)
            store.restore(bookmarks: bookmarks, tags: tags)
            restoreSuccess = true
        } catch {
            restoreError = error.localizedDescription
        }
    }
}

// Lightweight wrapper so HotKeyManager can be used as an EnvironmentObject
final class HotKeyManagerWrapper: ObservableObject {
    let manager = HotKeyManager()
}
