import Foundation

enum Constants {
    static let appName = "Tabby"
    static let bundleID = "com.tabby.app"

    enum Paths {
        static var appSupportURL: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return base.appendingPathComponent(Constants.appName, isDirectory: true)
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

        static var importHistoryFile: URL {
            appSupportURL.appendingPathComponent("imported_files.json")
        }

        static var importLockFile: URL {
            appSupportURL.appendingPathComponent(".import-in-progress")
        }
    }

    enum PopoverSize {
        static let width: CGFloat = 380
        static let height: CGFloat = 560
    }

    enum PopoverLayout {
        static let toolbarTop: CGFloat = 14
        static let toolbarBottom: CGFloat = 10
        static let footerBottom: CGFloat = 14
        static let heroVertical: CGFloat = 20
        static let heroHorizontal: CGFloat = 16
    }

    static let maxBackups = 5
    static let faviconFetchTimeout: TimeInterval = 5.0

    static let streamThresholdBytes = 1_000_000
    static let largeImportThreshold = 100
    static let softWarnImportCount = 5_000
    static let hardImportLimit = 50_000
    static let importBatchSize = 200
    static let successAutoDismissSeconds = 4.0
    static let parseYieldInterval = 200

    enum UserDefaultsKeys {
        static let resumeBrowserImportAfterFDA = "tabby.resumeBrowserImportAfterFDA"
    }
}

extension Notification.Name {
    static let tabbyDroppedFile = Notification.Name("tabbyDroppedFile")
}
