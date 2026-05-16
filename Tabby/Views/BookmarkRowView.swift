import SwiftUI

struct BookmarkRowView: View {
    let bookmark: Bookmark
    let tagObjects: [Tag]
    let isCompact: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                // Favicon
                Group {
                    if let img = bookmark.faviconImage {
                        Image(nsImage: img.resized(to: NSSize(width: 16, height: 16)))
                            .interpolation(.high)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 18, height: 18)

                // Text content
                VStack(alignment: .leading, spacing: isCompact ? 1 : 2) {
                    Text(bookmark.displayTitle)
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !isCompact {
                        Text(bookmark.urlDomain)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if !bookmark.tags.isEmpty {
                        TagPillsView(tagNames: bookmark.tags, tagObjects: tagObjects)
                    }
                }

                Spacer()

                // Right side metadata + actions
                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Edit")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Delete")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    if bookmark.clickCount > 0 {
                        Text("\(bookmark.clickCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.quaternary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isCompact ? 6 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(isHovered: isHovered)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Edit") { onEdit() }
            Divider()
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
