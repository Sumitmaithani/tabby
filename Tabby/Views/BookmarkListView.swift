import SwiftUI

struct BookmarkListView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var settingsStore: SettingsStore
    var onEdit: (Bookmark) -> Void
    @Binding var showImportSheet: Bool

    @State private var deleteTarget: Bookmark? = nil

    var body: some View {
        let bookmarks = store.filteredBookmarks
        let isFiltered = !store.searchText.isEmpty || store.selectedTag != nil

        if bookmarks.isEmpty {
            EmptyStateView(isFiltered: isFiltered, showImportSheet: $showImportSheet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(bookmarks) { bookmark in
                        BookmarkRowView(
                            bookmark: bookmark,
                            tagObjects: store.tags,
                            isCompact: settingsStore.settings.compactView,
                            onOpen: { store.open(bookmark) },
                            onEdit: { onEdit(bookmark) },
                            onDelete: { deleteTarget = bookmark }
                        )
                        if bookmark.id != bookmarks.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(deleteTarget?.displayTitle ?? "")\"?",
                isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let b = deleteTarget { store.delete(b) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
        }
    }
}
