import Foundation
import Carbon

struct AppSettings: Codable {
    var hotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)  // ⌘⇧
    var hotKeyCode: UInt32 = 37           // L key
    var defaultExportFolder: String = ""
    var fetchFavicons: Bool = true
    var launchAtLogin: Bool = false
    var autoExportEnabled: Bool = false
    var autoExportInterval: AutoExportInterval = .weekly
    var autoExportFolder: String = ""
    var compactView: Bool = false

    enum AutoExportInterval: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
    }
}
