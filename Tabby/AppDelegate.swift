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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupHotKey()
        settingsStore.applyTheme()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        if let image = NSImage(named: "TabbyMenuBar") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        }
        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "Tabby (⌘⇧L)"
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
                    self.openPopover(relativeTo: button)
                }
            }
        }
    }
}
