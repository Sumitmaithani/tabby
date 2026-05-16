import Foundation
import Carbon

// Registers a system-wide keyboard shortcut using the Carbon Event Manager.
// This works without accessibility entitlements for simple hotkeys.
final class HotKeyManager {
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onTriggered: (() -> Void)?

    private static let hotKeySignature: OSType = fourCharCode("LSTK")
    private static let hotKeyID: UInt32 = 1

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var hkID = EventHotKeyID()
        hkID.signature = HotKeyManager.hotKeySignature
        hkID.id = HotKeyManager.hotKeyID

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )
        guard status == noErr else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // Store self as unretained pointer for the Carbon callback
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { manager.onTriggered?() }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )
    }

    func unregister() {
        if let ref = eventHotKeyRef {
            UnregisterEventHotKey(ref)
            eventHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    deinit { unregister() }
}

private func fourCharCode(_ string: String) -> OSType {
    assert(string.count == 4)
    var result: OSType = 0
    for char in string.unicodeScalars {
        result = (result << 8) + OSType(char.value)
    }
    return result
}
