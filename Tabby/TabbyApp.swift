import SwiftUI

@main
struct TabbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — the app lives entirely in the menu bar.
        // Settings are accessed through the popover's gear button.
        Settings { EmptyView() }
    }
}
