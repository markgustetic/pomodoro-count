import Carbon.HIToolbox

/// A single system-wide hotkey backed by Carbon's `RegisterEventHotKey`.
/// This works from a menu-bar (accessory) app without Accessibility permission.
/// The press callback fires on the main thread.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPress: () -> Void

    /// Returns nil if the combo could not be registered (e.g. already taken).
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                Unmanaged<HotKeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .onPress()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x504F4D4F), id: 1)  // 'POMO'
        let regStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
