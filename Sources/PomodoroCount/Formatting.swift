import Foundation

// MARK: - Formatting helpers

@MainActor
extension AppModel {

    static func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(ceil(t)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The same duration in words, for VoiceOver — "50:00" would otherwise be
    /// read as bare digits.
    static func spokenDuration(_ t: TimeInterval) -> String {
        let total = max(0, Int(ceil(t)))
        let minutes = total / 60, seconds = total % 60
        let m = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        let s = "\(seconds) \(seconds == 1 ? "second" : "seconds")"
        if minutes == 0 { return s }
        if seconds == 0 { return m }
        return "\(m) \(s)"
    }

    /// Backs both the History day list and the header's date — the two read
    /// identically by design, so they share one formatter.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return Self.dayFormatter.string(from: date)
    }

    var shortDateString: String { Self.dayFormatter.string(from: Date()) }
}
