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

    static func action(phase: Phase) -> Action {
        switch phase {
        // Armed and running breaks alike: `.breakReady` is a break waiting to
        // be taken, `.breakTime` one under way or paused. Neither should
        // survive the night.
        case .breakReady, .breakTime: return .resetToIdle
        // `.work` even while running — see the focus-session test.
        case .idle, .work:            return .none
        }
    }
}
