/// What a click on a category row should do.
///
/// Pure and total over its inputs — the same shape as `Reorder.destination`
/// and `CategoryAdvance.next` — because the interesting half of this rule is
/// the two cases where the answer is *nothing*, and a rule living inside a
/// `Button`'s closure cannot be tested at all.
enum TargetPick {

    enum Action: Equatable {
        /// Aim the session target at the clicked category.
        case aim
        /// Hand control back to the ranking: clear the pin, restart at the top.
        case release
        /// Change nothing.
        case ignore
    }

    /// - Parameters:
    ///   - isAlreadyTarget: the clicked row is the one finished pomodoros
    ///     already land on.
    ///   - pinned: `settings.targetPinned` — the user aimed at a category that
    ///     was already met, which reads as "let me overshoot here".
    ///   - autoAdvance: `settings.autoAdvanceTarget` — the ranking is driving.
    static func action(isAlreadyTarget: Bool,
                       pinned: Bool,
                       autoAdvance: Bool) -> Action {
        guard isAlreadyTarget else { return .aim }
        // A second click releases a pin and does nothing else. Routing an
        // *unpinned* re-click to the release would call
        // `restartFromTopOfRanking()`, which aims at the top unmet category —
        // so clicking the row you are already working in would move the target
        // off it and onto another one. A click must never aim somewhere the
        // user did not click.
        //
        // And with `autoAdvanceTarget` off there is no ranking to hand back to,
        // which is why the dropdown this replaces only offered "Follow the
        // order" while that rule was running.
        guard pinned, autoAdvance else { return .ignore }
        return .release
    }
}
