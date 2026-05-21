import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: Any?

    let store = BookmarkStore()
    let settingsStore = SettingsStore()
    let hotKeyWrapper = HotKeyManagerWrapper()
    lazy var importCoordinator = ImportCoordinator(store: store, settingsStore: settingsStore)
    private var firstRunWindow: FirstRunWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupHotKey()
        checkCrashRecovery()
        store.migrateLegacyBrowserTagsIfNeeded(settingsStore: settingsStore)
        if settingsStore.settings.fetchFavicons {
            store.fetchMissingFaviconsInBackground()
        }
        presentFirstRunIfNeeded()
    }

    private func presentFirstRunIfNeeded() {
        let s = settingsStore.settings
        let isEmpty = store.bookmarks.filter { !$0.isArchived }.isEmpty
        guard !s.hasCompletedFirstRunImport, !s.hasSkippedImportOnboarding, isEmpty else { return }

        let controller = FirstRunWindowController(
            store: store,
            settingsStore: settingsStore,
            coordinator: importCoordinator
        )
        firstRunWindow = controller
        controller.present()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        let size = NSSize(width: 22, height: 22)
        if let image = NSImage(named: "TabbyMenuBar") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)

            let dragView = DraggableStatusItemView(image: image, size: size)
            dragView.onClick = { [weak self] in
                self?.togglePopover()
            }
            dragView.onFileDrop = { [weak self] url in
                self?.handleFileDrop(url)
            }
            button.subviews.forEach { $0.removeFromSuperview() }
            dragView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            button.addSubview(dragView)
            button.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }

        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Tabby (⌘⇧L)"
    }

    private func handleFileDrop(_ url: URL) {
        if popover?.isShown != true, let button = statusItem?.button {
            openPopover(relativeTo: button)
        }
        importCoordinator.ingest(url)
        NotificationCenter.default.post(name: .tabbyDroppedFile, object: nil, userInfo: ["url": url])
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(
            width: Constants.PopoverSize.width,
            height: Constants.PopoverSize.height
        )
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(hotKeyWrapper)
                .environmentObject(importCoordinator)
        )
        self.popover = popover
    }

    // MARK: - Toggle

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: button)
        }
    }

    func openPopover(relativeTo button: NSView) {
        guard let popover else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover?.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Hotkey

    private func setupHotKey() {
        let s = settingsStore.settings
        hotKeyWrapper.manager.register(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers)
        hotKeyWrapper.manager.onTriggered = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                if self.popover?.isShown == true {
                    self.closePopover()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    self.openPopover(relativeTo: button)
                }
            }
        }
    }

    // MARK: - Opt-A crash recovery

    private func checkCrashRecovery() {
        guard let payload = ImportCoordinator.checkCrashRecoveryLock() else { return }

        let alert = NSAlert()
        alert.messageText = "Incomplete import detected"
        alert.informativeText = "Tabby was interrupted while importing \"\(payload.filename)\" (\(payload.bookmarkCount) bookmarks). Your library was rolled back. You can try importing again or discard this notice."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            ImportCoordinator.discardCrashRecoveryLock()
        }
    }
}
