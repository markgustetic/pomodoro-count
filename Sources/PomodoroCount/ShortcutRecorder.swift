import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A click-to-record control for a global shortcut. Click it, then press the
/// combo. Requires at least one modifier (so a bare key can't hijack typing).
/// Esc cancels; the event monitor consumes keys only while recording.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press keys…  (Esc to cancel)" : shortcut.display)
                .font(.callout.monospaced())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear(perform: stop)
        .accessibilityLabel("Global shortcut")
        .accessibilityValue(recording ? "Recording. Press a key combination, or Escape to cancel."
                                      : shortcut.spokenDisplay)
        .accessibilityHint(recording ? "" : "Activate to record a new key combination")
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)   // returns nil to swallow the key while recording
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard recording else { return event }

        // Esc cancels without changing anything.
        if event.keyCode == UInt32(kVK_Escape) {
            stop()
            return nil
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else {
            NSSound.beep()   // needs at least one modifier
            return nil
        }

        shortcut = Shortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers(from: flags),
            label: keyLabel(for: event))
        stop()
        return nil
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }

    private func keyLabel(for event: NSEvent) -> String {
        if let named = Self.specialKeys[Int(event.keyCode)] { return named }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? "?" : chars.uppercased()
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]
}
