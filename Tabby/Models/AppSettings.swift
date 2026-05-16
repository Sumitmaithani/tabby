import Foundation

struct AppSettings: Codable {
    var useICloudSync: Bool = false
    var hotKeyModifiers: UInt32 = 0xB00  // Cmd + Shift
    var hotKeyCode: UInt32 = 37           // L key
    var defaultExportFolder: String = ""
    var fetchFavicons: Bool = true
    var launchAtLogin: Bool = false
    var themeOverride: ThemeOverride = .system
    var autoExportEnabled: Bool = false
    var autoExportInterval: AutoExportInterval = .weekly
    var autoExportFolder: String = ""
    var compactView: Bool = false

    enum ThemeOverride: String, Codable, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
    }

    enum AutoExportInterval: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
    }
}
