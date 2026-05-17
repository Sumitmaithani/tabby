import Foundation
import Combine
import SwiftUI
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }

    private let dataService = DataService.shared

    init() {
        settings = dataService.loadSettings()
    }

    private func saveSettings() {
        try? dataService.saveSettings(settings)
    }

    // MARK: - Launch at login (macOS 13+)

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Launch-at-login failed — silently no-op; user can set manually
            }
        }
    }
}
