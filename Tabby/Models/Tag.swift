import Foundation
import SwiftUI

struct Tag: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = "#007AFF") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    static let palette: [String] = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30",
        "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00",
        "#30B0C7", "#32ADE6"
    ]
}
