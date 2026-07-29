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
            after: .named("Work"), in: rows(work: (4, 4), music: (0, 1)))
        #expect(next == .named("Music"))
    }

    /// A met category at the end of the list looks back at unfinished ones above
    /// it, rather than giving up because it ran out of rows.
    @Test func wrapsPastTheEndOfTheList() {
        let next = CategoryAdvance.next(
            after: .named("Music"), in: rows(work: (1, 4), music: (1, 1)))
        #expect(next == .named("Work"))
    }

    /// A goal of 0 means "tracked without a target", so `isMet` is false for it
    /// forever — landing there would be a sink the rotation could never leave.
    @Test func skipsCategoriesWithNoGoal() {
        let next = CategoryAdvance.next(
            after: .named("Work"),
            in: rows(work: (4, 4), music: (0, 0), bucket: (0, 2)))
        #expect(next == .fallback)
    }

    @Test func advancesIntoTheBucketWhenItCarriesAGoal() {
        let next = CategoryAdvance.next(
            after: .named("Music"),
            in: rows(work: (4, 4), music: (1, 1), bucket: (0, 3)))
        #expect(next == .fallback)
    }

    @Test func skipsTheBucketWhenItHasNoGoal() {
        let next = CategoryAdvance.next(
            after: .named("Music"),
            in: rows(work: (0, 4), music: (1, 1), bucket: (0, 0)))
        #expect(next == .named("Work"))
    }

    /// The whole day's plan is met, so the target stays where it is and further
    /// pomodoros overshoot there.
    @Test func staysPutWhenNothingIsAvailable() {
        let next = CategoryAdvance.next(
            after: .named("Work"),
            in: rows(work: (4, 4), music: (1, 1), bucket: (0, 0)))
        #expect(next == nil)
    }

    @Test func staysPutWhenTheCurrentTargetIsNotMet() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (3, 4), music: (0, 1)))
        #expect(next == nil)
    }

    /// A goal met by some *other* category is not this rule's business.
    @Test func staysPutWhenOnlyAnotherCategoryIsMet() {
        let next = CategoryAdvance.next(
            after: .named("Work"), in: rows(work: (0, 4), music: (1, 1)))
        #expect(next == nil)
    }

    /// `todayProgress` is empty while categories are off, and a target with no
    /// row has nowhere to start the search from.
    @Test func staysPutWhenThereAreNoRows() {
        #expect(CategoryAdvance.next(after: .named("Work"), in: []) == nil)
    }

    /// The bucket is matched by `isFallback`, not by name — its row carries the
    /// user's chosen fallback name, which `.fallback` knows nothing about.
    @Test func advancesFromTheBucketWhenItIsTheMetTarget() {
        let next = CategoryAdvance.next(
            after: .fallback,
            in: rows(work: (0, 4), music: (1, 1), bucket: (2, 2)))
        #expect(next == .named("Work"))
    }

    /// Names are compared normalized everywhere else in this codebase; a target
    /// spelled differently from its row must still be found.
    @Test func matchesTheTargetIgnoringCaseAndWhitespace() {
        let next = CategoryAdvance.next(
            after: .named("  work "), in: rows(work: (4, 4), music: (0, 1)))
        #expect(next == .named("Music"))
    }
}
