import Testing
@testable import PomodoroCount

/// The rule is pure, so none of this needs a model, a store or the main actor.
@Suite struct CategoryAdvanceTests {

    /// A row shaped the way `todayProgress` builds them. `id` plays no part in
    /// the rule, so it just mirrors the name.
    private func row(_ name: String, done: Int, goal: Int,
                     isFallback: Bool = false) -> CategoryProgress {
        CategoryProgress(id: name, name: name, done: done, goal: goal,
                         isFallback: isFallback, isSessionTarget: false)
    }

    /// Two categories and the bucket, in the order `todayProgress` returns them.
    private func rows(work: (Int, Int) = (0, 4),
                      music: (Int, Int) = (0, 1),
                      bucket: (Int, Int) = (0, 0)) -> [CategoryProgress] {
        [row("Work", done: work.0, goal: work.1),
         row("Music", done: music.0, goal: music.1),
         row("General", done: bucket.0, goal: bucket.1, isFallback: true)]
    }

    @Test func advancesToTheNextUnmetCategory() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (4, 4), music: (0, 1)),
            pinned: false)
        #expect(next == .named("Music"))
    }

    /// Three categories, so the rule has somewhere both above *and* below the
    /// current target to go. `rows(…)` above can't express that: its middle
    /// category is the only one that can sit between two others.
    private func ranked(_ a: (Int, Int), _ b: (Int, Int), _ c: (Int, Int))
        -> [CategoryProgress] {
        [row("A", done: a.0, goal: a.1),
         row("B", done: b.0, goal: b.1),
         row("C", done: c.0, goal: c.1),
         row("General", done: 0, goal: 0, isFallback: true)]
    }

    /// The whole point of the change. The list is a priority ranking, so a met
    /// target hands off to the highest-ranked category with a goal left — *up*
    /// the list, past unfinished work, rather than onwards to whatever happens
    /// to sit below it. The old rotation answered `C` here.
    @Test func handsOffToTheHighestRankedUnmetCategory() {
        let next = CategoryAdvance.next(
            after: .named("B"), in: ranked((0, 1), (1, 1), (0, 1)), pinned: false)
        #expect(next == .named("A"))
    }

    /// A pin means the user pointed the target at a category they had already
    /// finished, which can only mean "let me overshoot here". Nothing moves.
    @Test func staysPutWhilePinned() {
        let next = CategoryAdvance.next(
            after: .named("B"), in: ranked((0, 1), (1, 1), (0, 1)), pinned: true)
        #expect(next == nil)
    }

    @Test func theTopUnmetRowIsTheHighestRankedOneWithAGoalLeft() {
        #expect(CategoryAdvance.topUnmet(in: ranked((1, 1), (0, 1), (0, 1)))
                == .named("B"))
    }

    @Test func thereIsNoTopUnmetRowWhenEveryGoalIsMet() {
        #expect(CategoryAdvance.topUnmet(in: ranked((1, 1), (1, 1), (1, 1))) == nil)
    }

    /// `isMet` is how `pickTarget` tells the two kinds of hand pick apart, so it
    /// has to answer for the bucket and for an absent row too.
    @Test func isMetAnswersForEveryKindOfTarget() {
        let rows = self.rows(work: (4, 4), music: (0, 1), bucket: (2, 2))
        #expect(CategoryAdvance.isMet(.named("Work"), in: rows))
        #expect(!CategoryAdvance.isMet(.named("Music"), in: rows))
        #expect(CategoryAdvance.isMet(.fallback, in: rows))
        #expect(!CategoryAdvance.isMet(.named("Nowhere"), in: rows))
    }

    /// A goal of 0 can never be met, so picking one never pins — the other half
    /// of "goal-0 needs no special case" is that the advance can't fire on it
    /// either, which `staysPutWhenTheCurrentTargetIsNotMet` already covers.
    @Test func aGoalOfZeroIsNeverMet() {
        #expect(!CategoryAdvance.isMet(.named("Music"),
                                       in: rows(work: (0, 4), music: (3, 0))))
    }

    /// A met category at the end of the list still finds unfinished ones above
    /// it. Under the old rotation this was the wrap-around case; under a
    /// ranking it is just "search from the top", which is the same answer for a
    /// less interesting reason.
    @Test func handsBackUpToAnUnfinishedCategoryAboveIt() {
        let next = CategoryAdvance.next(
            after: .named("Music"), in: rows(work: (1, 4), music: (1, 1)),
            pinned: false)
        #expect(next == .named("Work"))
    }

    /// A goal of 0 means "tracked without a target", so `isMet` is false for it
    /// forever — landing there would be a sink the rotation could never leave.
    @Test func skipsCategoriesWithNoGoal() {
        let next = CategoryAdvance.next(
            after: .named("Work"),
            in: rows(work: (4, 4), music: (0, 0), bucket: (0, 2)), pinned: false)
        #expect(next == .fallback)
    }

    @Test func advancesIntoTheBucketWhenItCarriesAGoal() {
        let next = CategoryAdvance.next(
            after: .named("Music"),
            in: rows(work: (4, 4), music: (1, 1), bucket: (0, 3)), pinned: false)
        #expect(next == .fallback)
    }

    @Test func skipsTheBucketWhenItHasNoGoal() {
        let next = CategoryAdvance.next(
            after: .named("Music"),
            in: rows(work: (0, 4), music: (1, 1), bucket: (0, 0)), pinned: false)
        #expect(next == .named("Work"))
    }

    /// The whole day's plan is met, so the target stays where it is and further
    /// pomodoros overshoot there.
    @Test func staysPutWhenNothingIsAvailable() {
        let next = CategoryAdvance.next(
            after: .named("Work"),
            in: rows(work: (4, 4), music: (1, 1), bucket: (0, 0)), pinned: false)
        #expect(next == nil)
    }

    @Test func staysPutWhenTheCurrentTargetIsNotMet() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (3, 4), music: (0, 1)),
            pinned: false)
        #expect(next == nil)
    }

    /// A goal met by some *other* category is not this rule's business.
    @Test func staysPutWhenOnlyAnotherCategoryIsMet() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (0, 4), music: (1, 1)),
            pinned: false)
        #expect(next == nil)
    }

    /// `todayProgress` is empty while categories are off, and a target with no
    /// row has nowhere to start the search from.
    @Test func staysPutWhenThereAreNoRows() {
        #expect(CategoryAdvance.next(after: .named("Work"), in: [], pinned: false) == nil)
    }

    /// The bucket is matched by `isFallback`, not by name — its row carries the
    /// user's chosen fallback name, which `.fallback` knows nothing about.
    @Test func advancesFromTheBucketWhenItIsTheMetTarget() {
        let next = CategoryAdvance.next(
            after: .fallback,
            in: rows(work: (0, 4), music: (1, 1), bucket: (2, 2)), pinned: false)
        #expect(next == .named("Work"))
    }

    /// Names are compared normalized everywhere else in this codebase; a target
    /// spelled differently from its row must still be found.
    @Test func matchesTheTargetIgnoringCaseAndWhitespace() {
        let next = CategoryAdvance.next(
            after: .named("  work "), in: rows(work: (4, 4), music: (0, 1)),
            pinned: false)
        #expect(next == .named("Music"))
    }
}
