import AppKit
import Foundation

enum FullDiskAccessChecker {
    private static var safariBookmarksProbe: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist", isDirectory: false)
    }

    /// Returns true when Tabby can read FDA-protected user Library paths.
    static func isGranted() -> Bool {
        let url = safariBookmarksProbe
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Safari not installed — still try reading Application Support as secondary probe.
            return canReadApplicationSupport()
        }
        do {
            _ = try Data(contentsOf: url, options: .mappedIfSafe)
            return true
        } catch {
            return canReadApplicationSupport()
        }
    }

    private static func canReadApplicationSupport() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        return FileManager.default.isReadableFile(atPath: probe.path)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func markResumeAfterGrant() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.resumeBrowserImportAfterFDA)
    }

    static func consumeResumeAfterGrant() -> Bool {
        let key = Constants.UserDefaultsKeys.resumeBrowserImportAfterFDA
        let value = UserDefaults.standard.bool(forKey: key)
        if value {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return value
    }

    static func requestRelaunch() {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
