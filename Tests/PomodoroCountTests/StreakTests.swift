import Testing
import Foundation
@testable import PomodoroCount

/// The streak: consecutive days with at least one pomodoro, ending today —
/// or ending yesterday, because a streak must not read as broken at midnight
/// before today's first pomodoro has had a chance to happen.
@MainActor
@Suite struct StreakTests {

    /// A record at noon `daysAgo` days ago — noon so no timezone arithmetic
    /// can nudge it across a day boundary.
    private func record(daysAgo: Int) -> Record {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        return Record(at: cal.date(byAdding: .hour, value: 12, to: day)!, source: "manual")
    }

    @Test func noRecordsMeansNoStreak() {
        let (m, _) = makeModel()
        #expect(m.streakDays == 0)
    }

    @Test func todayAloneIsAStreakOfOne() {
        let (m, _) = makeModel()
        m.records = [record(daysAgo: 0)]
        #expect(m.streakDays == 1)
    }

    @Test func consecutiveDaysAddUp() {
        let (m, _) = makeModel()
        m.records = [record(daysAgo: 0), record(daysAgo: 1), record(daysAgo: 2)]
        #expect(m.streakDays == 3)
    }

    /// Today being empty doesn't break the streak — it just hasn't grown yet.
    @Test func anOpenTodayKeepsYesterdaysStreakAlive() {
        let (m, _) = makeModel()
        m.records = [record(daysAgo: 1), record(daysAgo: 2), record(daysAgo: 3)]
        #expect(m.streakDays == 3)
    }

    @Test func aGapBreaksTheStreak() {
        let (m, _) = makeModel()
        m.records = [record(daysAgo: 0), record(daysAgo: 2), record(daysAgo: 3)]
        #expect(m.streakDays == 1, "the gap at yesterday cuts the streak to just today")
    }

    @Test func aStreakThatEndedBeforeYesterdayIsOver() {
        let (m, _) = makeModel()
        m.records = [record(daysAgo: 2), record(daysAgo: 3)]
        #expect(m.streakDays == 0)
    }

    @Test func severalRecordsOnOneDayCountOnce() {
        let (m, _) = makeModel()
        m.records = [record(daysAgo: 0), record(daysAgo: 0), record(daysAgo: 1)]
        #expect(m.streakDays == 2)
    }
}
