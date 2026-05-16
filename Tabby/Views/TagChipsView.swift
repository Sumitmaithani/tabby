import SwiftUI

struct TagChipsView: View {
    let tags: [String]
    let tagObjects: [Tag]
    @Binding var selectedTag: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TagChip(label: "All", color: .secondary, isSelected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(tags, id: \.self) { name in
                    let tag = tagObjects.first { $0.name == name }
                    TagChip(
                        label: name,
                        color: tag?.color ?? .blue,
                        isSelected: selectedTag == name
                    ) {
                        selectedTag = selectedTag == name ? nil : name
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 30)
    }
}

private struct TagChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? color : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// Inline compact tag pills used in bookmark rows
struct TagPillsView: View {
    let tagNames: [String]
    let tagObjects: [Tag]
    var compact = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tagNames.prefix(compact ? 2 : tagNames.count), id: \.self) { name in
                let tag = tagObjects.first { $0.name == name }
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tag?.color ?? .blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill((tag?.color ?? .blue).opacity(0.12))
                    )
            }
            if compact && tagNames.count > 2 {
                Text("+\(tagNames.count - 2)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
