import SwiftUI
import AppKit

// MARK: - Color from hex string
extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return "#007AFF" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Date formatting
extension Date {
    var relativeDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    var isoString: String {
        ISO8601DateFormatter().string(from: self)
    }
}

// MARK: - String URL validation
extension String {
    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    var normalizedURL: String {
        if hasPrefix("http://") || hasPrefix("https://") { return self }
        return "https://\(self)"
    }

    func normalizedForBookmark() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        return "https://\(trimmed)"
    }
}

// MARK: - View modifiers
extension View {
    func cardStyle() -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    func hoverHighlight(isHovered: Bool) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
    }
}

// MARK: - NSImage resizing
extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
