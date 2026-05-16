import SwiftUI

struct EmptyStateView: View {
    let isFiltered: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isFiltered ? "magnifyingglass" : "bookmark.slash")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(isFiltered ? "No results" : "No bookmarks yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Text(isFiltered
                     ? "Try a different search or tag filter."
                     : "Paste a URL in the link field above and press Return.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
