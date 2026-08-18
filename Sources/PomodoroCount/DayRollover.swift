import Foundation

/// What a calendar-day change should do to the timer.
///
/// A break belongs to the day that earned it: an app left overnight on an
/// armed or running break used to still be on that break in the morning, with
/// the long-break cycle counting yesterday's sessions. A new day starts on
/// focus.
///
/// The `switch` is exhaustive on purpose, following `StatusIcon.glyph`: a
/// fifth `Phase` case has to be given a rule here, rather than inheriting
/// `.none` by default and being noticed months later as a break that outlived
/// its day.
enum DayRollover {
    enum Action: Equatable {
        /// Leave the timer as it is.
        case none
        /// Stop the timer, drop to `.idle`, and restart the long-break cycle.
        case resetToIdle
    }

    /// - Parameters:
    ///   - phase: the timer's current phase.
    ///   - breakEnteredOn: when the current break phase began, or nil when the
    ///     timer is not on a break.
    ///   - newDay: the start of the day that has just begun.
    ///
    /// A break armed *on the new day itself* is not a leftover, and must
    /// survive. This is not hypothetical: a focus session running across a
    /// sleep that crosses midnight completes when the Mac wakes, and the wake
    /// notification that reports the new day is the same one that lets the
    /// overdue timer fire. Their order is unspecified, so without this the
    /// just-earned break survived or was wiped depending on run-loop
    /// scheduling.
    ///
    /// A nil stamp on a break phase reads as a leftover. Every path into
    /// `.breakReady` and `.breakTime` sets it, so nil is unreachable — and if
    /// a new path ever forgets, clearing a stale break is the safer failure.
    static func action(phase: Phase, breakEnteredOn: Date?, newDay: Date) -> Action {
        switch phase {
        case .breakReady, .breakTime:
            guard let began = breakEnteredOn else { return .resetToIdle }
            return began < newDay ? .resetToIdle : .none
        case .idle, .work:
            return .none
        }
    }
}
