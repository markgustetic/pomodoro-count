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

    @Test func shortcutSurvivesACodableRoundTrip() throws {
        let original = Shortcut(keyCode: 12, carbonModifiers: UInt32(optionKey), label: "Q")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == original)
    }
}
