import Testing
@testable import PomodoroCount

/// What a click on a category row means, in the three-boolean space the row
/// can actually be in.
///
/// The two `.ignore` cases are why this is a type rather than an `if` inside a
/// `Button`: a rule that lives in a closure cannot be tested at all, and those
/// two are exactly where a plausible-looking implementation goes wrong.
@Suite struct TargetPickTests {

    /// The common case. Nothing about a pin matters when the click lands
    /// somewhere the target isn't.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func clickingAnotherRowAlwaysAims(pinned: Bool, autoAdvance: Bool) {
        #expect(TargetPick.action(isAlreadyTarget: false,
                                  pinned: pinned,
                                  autoAdvance: autoAdvance) == .aim)
    }

    /// The handback the dropdown's "Follow the order" entry used to carry.
    @Test func clickingThePinnedTargetAgainReleasesIt() {
        #expect(TargetPick.action(isAlreadyTarget: true,
                                  pinned: true,
                                  autoAdvance: true) == .release)
    }

    /// With the ranking switched off there is nothing to hand control back
    /// *to*, so the pin has nothing to hold out against and the click has
    /// nothing to do. Mirrors the dropdown, which only offered the handback
    /// while the rule was running.
    @Test func clickingThePinnedTargetDoesNothingWhileTheRuleIsOff() {
        #expect(TargetPick.action(isAlreadyTarget: true,
                                  pinned: true,
                                  autoAdvance: false) == .ignore)
    }

    /// The case that must not be routed to the release. `followTheOrder()`
    /// aims at the top unmet category, so releasing here would move the target
    /// off the row that was just clicked and onto a different one — a click
    /// aiming somewhere the user did not click.
    @Test(arguments: [false, true])
    func clickingAnUnpinnedTargetAgainChangesNothing(autoAdvance: Bool) {
        #expect(TargetPick.action(isAlreadyTarget: true,
                                  pinned: false,
                                  autoAdvance: autoAdvance) == .ignore)
    }
}
