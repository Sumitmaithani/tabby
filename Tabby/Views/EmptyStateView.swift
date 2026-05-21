import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var importCoordinator: ImportCoordinator

    let isFiltered: Bool
    @Binding var showImportSheet: Bool

    private var showOnboarding: Bool {
        !isFiltered && store.bookmarks.filter { !$0.isArchived }.isEmpty
            && !settingsStore.settings.hasSkippedImportOnboarding
    }

    var body: some View {
        Group {
            if showOnboarding {
                heroSection { OnboardingHeroView() }
            } else {
                heroSection { standardEmpty }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: importCoordinator.phase) { phase in
            if phase != .idle { showImportSheet = true }
        }
    }

    private func heroSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Constants.PopoverLayout.heroVertical)
            content()
                .padding(.horizontal, Constants.PopoverLayout.heroHorizontal)
            Spacer(minLength: Constants.PopoverLayout.heroVertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var standardEmpty: some View {
        VStack(spacing: 14) {
            Image(systemName: isFiltered ? "magnifyingglass" : "bookmark.slash")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(isFiltered ? "No results" : "No bookmarks yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if isFiltered {
                    Text("Try a different search or tag filter.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 10) {
                        Text("Paste a URL in the link field above and press Return.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Import from browsers") {
                            importCoordinator.startBrowserFlow()
                            showImportSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Import from file…") {
                            importCoordinator.phase = .idle
                            showImportSheet = true
                            importCoordinator.openFilePicker()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
