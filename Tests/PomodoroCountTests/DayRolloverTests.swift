import Testing
import Foundation
@testable import PomodoroCount

/// A break should not outlive the day it was earned in. The decision is
/// extracted from the notification handler so a fifth `Phase` case fails a
/// test here rather than quietly inheriting "do nothing" — the same reason
/// `StatusIcon.glyph` lives outside the drawing routine.
@MainActor
@Suite struct DayRolloverDecisionTests {

    @Test func anArmedBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakReady) == .resetToIdle)
    }

    @Test func aRunningBreakIsClearedByANewDay() {
        #expect(DayRollover.action(phase: .breakTime) == .resetToIdle)
    }

    @Test func idleIsLeftAlone() {
        #expect(DayRollover.action(phase: .idle) == .none)
    }

    /// A focus session in progress at midnight is real work about to become a
    /// record. Ending it would destroy that.
    @Test func aFocusSessionIsLeftAlone() {
        #expect(DayRollover.action(phase: .work) == .none)
    }
}
