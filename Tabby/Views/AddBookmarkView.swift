import SwiftUI

struct AddBookmarkView: View {
    @EnvironmentObject var store: BookmarkStore
    @EnvironmentObject var settingsStore: SettingsStore

    var editingBookmark: Bookmark? = nil
    let onDismiss: () -> Void
    var onSaved: (() -> Void)? = nil

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var notesText = ""
    @State private var selectedTags: Set<String> = []
    @State private var newTagName = ""
    @State private var newTagColor = Tag.palette[0]
    @State private var isFetchingMetadata = false
    @State private var urlError: String? = nil
    @FocusState private var urlFocused: Bool

    private var isEditing: Bool { editingBookmark != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Text(isEditing ? "Edit Bookmark" : "Add Bookmark")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if isFetchingMetadata {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // URL field
                    VStack(alignment: .leading, spacing: 4) {
                        Label("URL", systemImage: "link")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("https://example.com", text: $urlText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .focused($urlFocused)
                                .onChange(of: urlText) { new in
                                    urlError = nil
                                    if new.isValidURL {
                                        autoFetch(url: new)
                                    }
                                }
                                .onSubmit { validateURL() }

                            if !urlText.isEmpty {
                                Button { urlText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.background))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder((urlError != nil ? Color.red : Color(NSColor.separatorColor)).opacity(0.6), lineWidth: 0.5)
                        )

                        if let err = urlError {
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        }
                    }

                    // Title field
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Title", systemImage: "textformat")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("Auto-fetched or enter manually", text: $titleText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.background))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
                            )
                    }

                    // Notes field
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Notes", systemImage: "note.text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $notesText)
                            .font(.system(size: 12))
                            .frame(height: 60)
                            .padding(6)
                            .scrollContentBackground(.hidden)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.background))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
                            )
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Tags", systemImage: "tag")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        if store.tags.isEmpty {
                            Text("No tags yet — create one below.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(store.tags) { tag in
                                    let isSelected = selectedTags.contains(tag.name)
                                    Button {
                                        if isSelected { selectedTags.remove(tag.name) }
                                        else { selectedTags.insert(tag.name) }
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            Text(tag.name)
                                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        }
                                        .foregroundStyle(isSelected ? tag.color : .secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(isSelected ? tag.color.opacity(0.15) : Color.primary.opacity(0.06))
                                        )
                                        .overlay(Capsule().strokeBorder(isSelected ? tag.color.opacity(0.4) : Color.clear, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Add new tag inline
                        HStack(spacing: 6) {
                            TextField("New tag…", text: $newTagName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5))
                                .frame(maxWidth: 120)
                                .onSubmit { addNewTag() }

                            HStack(spacing: 4) {
                                ForEach(Tag.palette.prefix(5), id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: hex) ?? .blue)
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Circle().strokeBorder(newTagColor == hex ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1.5)
                                        )
                                        .onTapGesture { newTagColor = hex }
                                }
                            }

                            Button("Add", action: addNewTag)
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(isEditing ? "Save Changes" : "Add Bookmark") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: Constants.PopoverSize.width, height: Constants.PopoverSize.height)
        .onAppear { prefill() }
    }

    // MARK: - Helpers

    private func prefill() {
        guard let b = editingBookmark else {
            urlFocused = true
            // Pre-fill from clipboard if it looks like a URL
            if let clip = NSPasteboard.general.string(forType: .string), clip.isValidURL {
                urlText = clip
                autoFetch(url: clip)
            }
            return
        }
        urlText = b.url
        titleText = b.title
        notesText = b.notes
        selectedTags = Set(b.tags)
    }

    private func autoFetch(url: String) {
        guard settingsStore.settings.fetchFavicons else { return }
        Task {
            isFetchingMetadata = true
            let (title, _) = await FaviconService.shared.fetchMetadata(for: url)
            await MainActor.run {
                isFetchingMetadata = false
                if let title, titleText.isEmpty {
                    titleText = title
                }
            }
        }
    }

    private func validateURL() {
        let cleaned = urlText.trimmingCharacters(in: .whitespacesAndNewlines).normalizedForBookmark()
        if cleaned.isValidURL {
            urlText = cleaned
            urlError = nil
        } else {
            urlError = "Enter a valid URL (https://…)"
        }
    }

    private func addNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let tag = Tag(name: name, colorHex: newTagColor)
        store.addTag(tag)
        selectedTags.insert(name)
        newTagName = ""
    }

    private func save() {
        let cleaned = urlText.trimmingCharacters(in: .whitespacesAndNewlines).normalizedForBookmark()
        guard !cleaned.isEmpty else { return }
        guard cleaned.isValidURL else {
            urlError = "Enter a valid URL (e.g. example.com or https://…)"
            return
        }
        urlText = cleaned

        if var b = editingBookmark {
            b.url = cleaned
            b.title = titleText.trimmingCharacters(in: .whitespaces)
            b.notes = notesText.trimmingCharacters(in: .whitespaces)
            b.tags = Array(selectedTags)
            store.update(b)
        } else {
            var b = Bookmark(
                title: titleText.trimmingCharacters(in: .whitespaces),
                url: cleaned,
                tags: Array(selectedTags),
                notes: notesText.trimmingCharacters(in: .whitespaces)
            )
            store.addBookmark(b)
            if settingsStore.settings.fetchFavicons {
                Task { await store.fetchMetadata(for: b, fetchFavicons: true) }
            }
        }
        store.searchText = ""
        store.selectedTag = nil
        store.persistImmediately()
        onSaved?()
        onDismiss()
    }
}

// MARK: - FlowLayout (tag wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
