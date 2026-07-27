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
}
