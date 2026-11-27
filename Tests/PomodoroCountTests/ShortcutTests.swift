import Testing
import Foundation
import Carbon.HIToolbox
@testable import PomodoroCount

@MainActor
@Suite struct ShortcutTests {

    @Test func defaultIsControlOptionCommandP() {
        let (m, _) = makeModel()
        #expect(m.settings.shortcut == .default)
        #expect(m.settings.shortcut.display == "⌃⌥⌘P")
        #expect(m.settings.globalShortcutEnabled)
    }

    /// Modifiers render in the order macOS shows them, whatever order they were
    /// recorded in: control, option, shift, command.
    @Test func modifiersRenderInMacOrder() {
        let all = Shortcut(
            keyCode: 49,
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            label: "Space")
        #expect(all.display == "⌃⌥⇧⌘Space")
    }

    @Test func displayHandlesASingleModifier() {
        #expect(Shortcut(keyCode: 35, carbonModifiers: UInt32(cmdKey), label: "P").display == "⌘P")
    }

    @Test func customShortcutPersists() {
        let (m, url) = makeModel()
        m.updateShortcut(Shortcut(
            keyCode: 49, carbonModifiers: UInt32(cmdKey | shiftKey), label: "Space"))
        #expect(AppModel(storeURL: url).settings.shortcut.display == "⇧⌘Space")
    }

    @Test func disablingTheShortcutPersists() {
        let (m, url) = makeModel()
        m.setGlobalShortcut(false)
        #expect(!AppModel(storeURL: url).settings.globalShortcutEnabled)
    }

    @Test func togglingTheShortcutBackOnIsSafe() {
        let (m, _) = makeModel()
        m.setGlobalShortcut(false)
        m.setGlobalShortcut(true)
        #expect(m.settings.globalShortcutEnabled)
    }

    // MARK: Which combos the recorder may register

    /// A global hotkey swallows its keystroke in every app. ⇧ and ⌥ are how
    /// ordinary characters get typed — ⇧P is a capital P, ⌥P is π — so on a
    /// typing key they are not enough: registering ⇧P made every capital P on
    /// the machine log a pomodoro instead of appearing.
    @Test func shiftOrOptionAloneOnATypingKeyIsRefused() {
        let p = UInt32(kVK_ANSI_P)
        #expect(!Shortcut.canBeGlobal(keyCode: p, carbonModifiers: UInt32(shiftKey)))
        #expect(!Shortcut.canBeGlobal(keyCode: p, carbonModifiers: UInt32(optionKey)))
        #expect(!Shortcut.canBeGlobal(keyCode: p, carbonModifiers: UInt32(shiftKey | optionKey)))
        #expect(!Shortcut.canBeGlobal(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(shiftKey)))
    }

    @Test func commandOrControlMakesAnyKeyAcceptable() {
        let p = UInt32(kVK_ANSI_P)
        #expect(Shortcut.canBeGlobal(keyCode: p, carbonModifiers: UInt32(cmdKey)))
        #expect(Shortcut.canBeGlobal(keyCode: p, carbonModifiers: UInt32(controlKey)))
        #expect(Shortcut.canBeGlobal(keyCode: p, carbonModifiers: UInt32(controlKey | shiftKey)))
        #expect(Shortcut.canBeGlobal(keyCode: Shortcut.default.keyCode,
                                     carbonModifiers: Shortcut.default.carbonModifiers))
    }

    /// A function key types nothing, so ⇧F5 or ⌥F5 takes no character away
    /// from anyone — the combos a keypad or a Stream Deck is likeliest to send.
    @Test func aFunctionKeyNeedsOnlySomeModifier() {
        #expect(Shortcut.canBeGlobal(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(shiftKey)))
        #expect(Shortcut.canBeGlobal(keyCode: UInt32(kVK_F13), carbonModifiers: UInt32(optionKey)))
    }

    /// The rule the recorder has always had, now stated in the same place.
    @Test func noModifierAtAllIsRefusedEvenOnAFunctionKey() {
        #expect(!Shortcut.canBeGlobal(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: 0))
        #expect(!Shortcut.canBeGlobal(keyCode: UInt32(kVK_F5), carbonModifiers: 0))
    }

    @Test func shortcutSurvivesACodableRoundTrip() throws {
        let original = Shortcut(keyCode: 12, carbonModifiers: UInt32(optionKey), label: "Q")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == original)
    }
}
