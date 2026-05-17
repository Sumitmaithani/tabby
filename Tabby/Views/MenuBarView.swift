import SwiftUI

private enum MenuScreen: Equatable {
    case list
    case add(Int)
    case edit(Bookmark)
    case settings
}

struct MenuBarView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var hotKeyWrapper: HotKeyManagerWrapper

    @State private var screen: MenuScreen = .list
    @State private var quickAddURL = ""
    @State private var nextAddBookmarkSession = 0

    var body: some View {
        Group {
            switch screen {
            case .list:
                listContent
            case .add(let session):
                NewBookmarkScreen(
                    session: session,
                    onDismiss: { screen = .list },
                    onSaved: {
                        store.searchText = ""
                        store.selectedTag = nil
                    }
                )
                .environmentObject(store)
                .environmentObject(settingsStore)
            case .edit(let bookmark):
                EditBookmarkScreen(
                    bookmark: bookmark,
                    onDismiss: { screen = .list }
                )
                .environmentObject(store)
                .environmentObject(settingsStore)
            case .settings:
                SettingsView(onDismiss: { screen = .list })
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(hotKeyWrapper)
            }
        }
        .frame(width: Constants.PopoverSize.width, height: Constants.PopoverSize.height)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onDisappear {
            // Popover closed — discard any in-progress add/edit screen state.
            screen = .list
        }
    }

    // MARK: - List

    private var listContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if !store.allTagNames.isEmpty {
                TagChipsView(
                    tags: store.allTagNames,
                    tagObjects: store.tags,
                    selectedTag: $store.selectedTag
                )
                .padding(.top, 6)
                .padding(.bottom, 4)
                Divider()
            }

            BookmarkListView(onEdit: { screen = .edit($0) })
                .environmentObject(store)
                .environmentObject(settingsStore)

            Divider()
            footer
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                TextField("Paste URL and press Return…", text: $quickAddURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(quickAddBookmark)

                if !quickAddURL.isEmpty {
                    Button { quickAddURL = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: quickAddBookmark) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Save URL")
                .disabled(quickAddURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)

                    TextField("Search bookmarks…", text: $store.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if !store.searchText.isEmpty {
                        Button { store.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))

                HStack(spacing: 6) {
                    Menu {
                        Picker("Sort by", selection: $store.sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort")

                    Button {
                        nextAddBookmarkSession += 1
                        screen = .add(nextAddBookmarkSession)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Add bookmark with details (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func quickAddBookmark() {
        var url = quickAddURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        url = url.normalizedForBookmark()
        guard url.isValidURL else { return }

        let bookmark = Bookmark(url: url)
        store.addBookmark(bookmark)
        store.searchText = ""
        store.selectedTag = nil
        store.persistImmediately()
        quickAddURL = ""

        if settingsStore.settings.fetchFavicons {
            Task { await store.fetchMetadata(for: bookmark, fetchFavicons: true) }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)

            Spacer()

            Button { screen = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit Tabby")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footerText: String {
        let count = store.bookmarks.filter { !$0.isArchived }.count
        if count == 0 { return "No bookmarks" }
        return "\(count) bookmark\(count == 1 ? "" : "s")"
    }
}

// Separate wrapper types so SwiftUI does not reuse @State between add and edit screens.
private struct NewBookmarkScreen: View {
    let session: Int
    let onDismiss: () -> Void
    var onSaved: (() -> Void)? = nil

    var body: some View {
        AddBookmarkView(onDismiss: onDismiss, onSaved: onSaved)
            .id(session)
    }
}

private struct EditBookmarkScreen: View {
    let bookmark: Bookmark
    let onDismiss: () -> Void

    var body: some View {
        AddBookmarkView(editingBookmark: bookmark, onDismiss: onDismiss)
            .id(bookmark.id)
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
