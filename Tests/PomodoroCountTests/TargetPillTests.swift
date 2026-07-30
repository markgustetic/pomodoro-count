import Testing
import AppKit
import SwiftUI
@testable import PomodoroCount

@MainActor
@Suite struct TargetPillTests {

    /// A model whose target pill reads "pinned to <name>" — the widest of the
    /// two promises, so the worst case for fitting.
    private func pinned(to name: String) -> AppModel {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: name, dailyGoal: 1)]
        m.settings.sessionTargetName = name
        m.settings.targetPinned = true
        m.settings.targetAimedOn = Date()
        return m
    }

    /// The width the panel's own popup button reports once it has been laid
    /// out for real — the control that actually overflows, not a stand-in for
    /// it. `.menuStyle(.borderlessButton)` backs the pill with an
    /// `NSPopUpButton`, so it is findable in the hosted view tree.
    private func renderedPillWidth(_ model: AppModel) -> CGFloat? {
        let hosting = NSHostingView(rootView: RootView(initialTab: .focus).environmentObject(model))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        // Controls only lay out once they belong to a window — same reason
        // `PreviewRenderer.rasterize` builds one.
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        return popUpButton(in: hosting)?.frame.width
    }

    private func popUpButton(in view: NSView) -> NSView? {
        for sub in view.subviews {
            if sub is NSPopUpButton { return sub }
            if let hit = popUpButton(in: sub) { return hit }
        }
        return nil
    }

    /// The bug: a long category name drew the pill wider than the card holding
    /// it (336pt against 244), which pushed the card past the panel's fixed
    /// 300pt and clipped both the card and the Start button.
    ///
    /// This is the one test that measures the control instead of asking
    /// `TargetPill` to check its own arithmetic, so it is also what keeps the
    /// budget honest: a `width(_:)` that guessed from character counts would
    /// satisfy every other test here and still overflow on the wide-glyph
    /// names below.
    @Test(arguments: [
        "Machine learning coursework and thesis revision block",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        "重构编译器的中间表示层并补齐相应的回归测试",
    ]) func aLongTargetNameKeepsThePillInsideItsCard(name: String) throws {
        let width = try #require(renderedPillWidth(pinned(to: name)))
        #expect(width <= TargetPill.maxWidth)
    }

    /// The same measurement in reverse: the constant the truncation budgets
    /// against is not a guess about this control, it is what the control does.
    /// A name short enough to need no shortening must still be drawn whole.
    @Test func ashortTargetNameIsDrawnWhole() throws {
        let model = pinned(to: "Bravo")
        let width = try #require(renderedPillWidth(model))
        #expect(width <= TargetPill.maxWidth)
        #expect(model.sessionTargetPillText == "pinned to Bravo")
    }

    // MARK: The shortening itself

    private let long = "Machine learning coursework and thesis revision block"

    /// Names of every shape, all of which have to come back inside the budget —
    /// wide glyphs and narrow ones, one long word and many short.
    @Test(arguments: [
        "Machine learning coursework and thesis revision block",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        "iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii",
        "Supercalifragilisticexpialidociousandthensomemoreforgoodmeasure",
        "重构编译器的中间表示层并补齐相应的回归测试",
    ]) func everyOverlongNameEndsUpInsideTheBudget(name: String) {
        let label = TargetPill.label(prefix: "pinned to ", name: name)
        #expect(TargetPill.width(label) + TargetPill.chrome <= TargetPill.maxWidth)
    }

    /// A name that already fits keeps every character, and gains no ellipsis.
    @Test func anameThatFitsIsLeftAlone() {
        #expect(TargetPill.label(prefix: "towards ", name: "Work") == "towards Work")
    }

    /// The promise is never what gets cut: it is the whole difference between
    /// the two kinds of hand pick, and the menu below repeats the names anyway.
    @Test func thePromiseSurvivesTheCut() {
        let label = TargetPill.label(prefix: "pinned to ", name: long)
        #expect(label.hasPrefix("pinned to "))
        #expect(label.hasSuffix("…"))
    }

    /// "pinned to " is wider than "towards ", so it has to buy that width out of
    /// the name rather than out of the panel — the two promises cannot both cut
    /// at the same character.
    @Test func thewiderPromiseLeavesLessRoomForTheName() {
        let pinned = TargetPill.label(prefix: "pinned to ", name: long)
        let towards = TargetPill.label(prefix: "towards ", name: long)
        #expect(pinned.count - "pinned to ".count < towards.count - "towards ".count)
    }

    /// A cut landing just after a word reads "… revision…", not "… revision …".
    ///
    /// Swept across every budget the pill can have rather than tried at one:
    /// which character the cut lands on is a function of the budget, so a single
    /// width would only prove the trim for the one place it happened to cut, and
    /// would keep passing with the trim taken out.
    @Test func theSpaceBeforeTheCutGoesWithIt() {
        for budget in stride(from: 60.0, through: TargetPill.maxWidth, by: 1) {
            let label = TargetPill.label(prefix: "towards ", name: long, maxWidth: budget)
            // The floor is not a cut after a space: with no room for any of the
            // name, "towards …" is the promise's own trailing space.
            guard label != "towards …" else { continue }
            #expect(!label.contains(" …"), "budget \(budget) cut after a space")
        }
    }

    /// A budget too narrow for any of the name at all still says which kind of
    /// target is in force, rather than collapsing to nothing.
    @Test func abudgetTooNarrowForTheNameStillNamesThePromise() {
        #expect(TargetPill.label(prefix: "pinned to ", name: long, maxWidth: 40) == "pinned to …")
    }

    /// Cutting by `Character` and not by scalar: a category named in emoji must
    /// not come back with half a family in it.
    @Test func thecutFallsOnCharacterBoundaries() {
        let name = String(repeating: "👨‍👩‍👧‍👦", count: 30)
        let label = TargetPill.label(prefix: "towards ", name: name)
        let head = String(label.dropFirst("towards ".count).dropLast())
        #expect(!head.isEmpty)
        #expect(name.hasPrefix(head))
    }

    /// The eye loses the tail of a long name; VoiceOver must not. The spoken
    /// value is the untruncated description, which is also what the existing
    /// `sessionTargetDescription` tests pin down.
    @Test func theSpokenValueKeepsWhatTheEyeLoses() {
        let model = pinned(to: long)
        #expect(model.sessionTargetDescription == "pinned to \(long)")
        #expect(model.sessionTargetPillText != model.sessionTargetDescription)
        #expect(model.sessionTargetPillText.hasSuffix("…"))
    }
}
