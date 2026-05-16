import Foundation

enum Constants {
    static let appName = "Tabby"
    static let bundleID = "com.tabby.app"

    enum Paths {
        static var appSupportURL: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return base.appendingPathComponent(Constants.appName, isDirectory: true)
        }

        static var iCloudURL: URL? {
            guard let base = FileManager.default.url(
                forUbiquityContainerIdentifier: nil
            ) else { return nil }
            return base.appendingPathComponent("Documents/\(Constants.appName)", isDirectory: true)
        }

        static var bookmarksFile: URL {
            appSupportURL.appendingPathComponent("bookmarks.json")
        }

        static var tagsFile: URL {
            appSupportURL.appendingPathComponent("tags.json")
        }

        static var settingsFile: URL {
            appSupportURL.appendingPathComponent("settings.json")
        }

        static var backupsDirectory: URL {
            appSupportURL.appendingPathComponent("backups", isDirectory: true)
        }
    }

    enum PopoverSize {
        static let width: CGFloat = 380
        static let height: CGFloat = 560
    }

    static let maxBackups = 5
    static let faviconFetchTimeout: TimeInterval = 5.0
}
