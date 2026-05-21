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
    var duplicatePolicy: DuplicatePolicy = .skip
    var autoBackupBeforeImport: Bool = true
    var hasSkippedImportOnboarding: Bool = false
    var hasCompletedFirstRunImport: Bool = false
    var lastBrowserImportDate: Date? = nil
    var lastBrowserImportSources: [String] = []
    var hasMigratedBrowserTagsToLeaf: Bool = false

    enum AutoExportInterval: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
    }
}
