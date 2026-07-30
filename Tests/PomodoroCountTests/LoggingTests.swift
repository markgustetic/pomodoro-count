import Testing
import Foundation
@testable import PomodoroCount

/// The headline feature: recording a pomodoro finished on external hardware.
@MainActor
@Suite struct LoggingTests {

    @Test func startsEmpty() {
        let (m, _) = makeModel()
        #expect(m.todayCount == 0)
        #expect(m.totalCount == 0)
        #expect(m.weekCount == 0)
    }

    @Test func logExternalCountsTowardToday() {
        let (m, _) = makeModel()
        m.logExternal()
        m.logExternal()
        m.logExternal()
        #expect(m.todayCount == 3)
        #expect(m.totalCount == 3)
    }

    @Test func logExternalMarksRecordsManual() {
        let (m, _) = makeModel()
        m.logExternal()
        #expect(m.records.allSatisfy { $0.source == "manual" })
    }

    @Test func logExternalStampsRecordsNow() {
        let (m, _) = makeModel()
        m.logExternal()
        let stamp = try! #require(m.records.first).at
        #expect(abs(stamp.timeIntervalSinceNow) < 5)
    }

    @Test func undoLastRemovesOne() {
        let (m, _) = makeModel()
        m.logExternal()
        m.logExternal()
        m.undoLast()
        #expect(m.todayCount == 1)
    }

    @Test func undoLastOnEmptyIsSafe() {
        let (m, _) = makeModel()
        m.logExternal()
        m.undoLast()
        m.undoLast()   // already empty
        #expect(m.todayCount == 0)
        #expect(m.totalCount == 0)
    }

    /// Undo means "the most recent pomodoro", which is not necessarily the last
    /// element of the array — a timer completion can land after a manual log
    /// that was backdated, and the newest one is what the user means to drop.
    @Test func undoLastRemovesTheNewestNotTheLastAppended() {
        let (m, _) = makeModel()
        let old = Record(at: .daysAgo(3), source: "manual")
        let newest = Record(at: Date(), source: "timer")
        m.records = [newest, old]   // newest deliberately first in the array
        m.undoLast()
        #expect(m.records.count == 1)
        #expect(m.records.first?.source == "manual")
    }

    @Test func eachRecordGetsADistinctIdentity() {
        let (m, _) = makeModel()
        m.logExternal()
        m.logExternal()
        #expect(Set(m.records.map(\.id)).count == 2)
    }

    // MARK: Per-category subtract

    @Test func unlogTodayRemovesFromTheNamedCategory() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3),
                                 Category(name: "Admin", dailyGoal: 3)]
        m.logExternal(to: .named("Writing"))
        m.logExternal(to: .named("Admin"))

        m.unlogToday(from: .named("Writing"))

        #expect(m.todayCount(inCategory: "Writing") == 0)
        #expect(m.todayCount(inCategory: "Admin") == 1)
    }

    /// The whole point of a per-category subtract: a newer pomodoro somewhere
    /// else is exactly the case the global "Undo last" gets wrong.
    @Test func unlogTodayIgnoresANewerRecordInAnotherCategory() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3),
                                 Category(name: "Admin", dailyGoal: 3)]
        m.records = [
            Record(at: .todayAt(hour: 9), source: "manual", category: "Writing"),
            Record(at: .todayAt(hour: 12), source: "manual", category: "Admin"),
        ]

        m.unlogToday(from: .named("Writing"))

        #expect(m.records.count == 1)
        #expect(m.records.first?.category == "Admin")
    }

    @Test func unlogTodayOnAnEmptyCategoryIsANoOp() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3)]

        m.unlogToday(from: .named("Writing"))
        m.unlogToday(from: .named("Writing"))

        #expect(m.records.isEmpty)
        #expect(m.todayCount == 0)
    }

    /// The row shows today, so the subtract adjusts today. Yesterday's history
    /// is not a reserve the counter can draw down.
    @Test func unlogTodayLeavesEarlierDaysAlone() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3)]
        m.records = [Record(at: .daysAgo(1), source: "manual", category: "Writing")]

        m.unlogToday(from: .named("Writing"))

        #expect(m.records.count == 1)
    }

    @Test func unlogTodayRemovesABucketRecord() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 3)]
        m.records = [
            Record(at: .todayAt(hour: 9), source: "manual", category: nil),
            Record(at: .todayAt(hour: 12), source: "manual", category: "Writing"),
        ]

        m.unlogToday(from: .fallback)

        #expect(m.records.count == 1)
        #expect(m.records.first?.category == "Writing")
    }

    /// A removal must not re-aim the session. The advance is forward-only on
    /// purpose: re-aiming because a count dropped would move the target out
    /// from under a Start the user has already pressed.
    ///
    /// Non-vacuous by construction, and the construction is fiddly, so it is
    /// worth saying why: `CategoryAdvance.next` returns nil unless the *current*
    /// target is met, so Admin has to be met for a mistaken `realignTarget()` to
    /// reach the ranking at all. Writing dropping to 1/2 then makes it the top
    /// unmet row, so that mistaken call would move the target Admin → Writing
    /// and this assertion would fail. An earlier version of this test left Admin
    /// unmet, and passed either way.
    @Test func unlogTodayLeavesTheSessionTargetAlone() {
        let (m, _) = makeModel()
        m.settings.categoriesEnabled = true
        m.settings.autoAdvanceTarget = true
        m.settings.categories = [Category(name: "Writing", dailyGoal: 2),
                                 Category(name: "Admin", dailyGoal: 1)]
        m.records = [
            Record(at: .todayAt(hour: 9), source: "manual", category: "Writing"),
            Record(at: .todayAt(hour: 10), source: "manual", category: "Writing"),
            Record(at: .todayAt(hour: 11), source: "manual", category: "Admin"),
        ]
        m.settings.targetAimedOn = Date()
        m.sessionTarget = .named("Admin")

        m.unlogToday(from: .named("Writing"))

        // Guards the guard: if the removal silently did nothing, the target
        // would be unchanged for the wrong reason.
        #expect(m.todayCount(inCategory: "Writing") == 1)
        #expect(m.sessionTarget == .named("Admin"))
    }
}
