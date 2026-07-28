import Foundation

// MARK: - Export

@MainActor
extension AppModel {

    /// The whole history as CSV, one row per pomodoro, oldest first. Lossless,
    /// so a spreadsheet can group it however the reader likes.
    func csvExport() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["timestamp,source,category"]
        for record in records.sorted(by: { $0.at < $1.at }) {
            lines.append([formatter.string(from: record.at),
                          record.source,
                          record.category ?? settings.fallbackName]
                .map(Self.csvField)
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `source` comes from a file the user can edit by hand, so quote defensively.
    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Suggested filename for an export.
    var csvFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "pomodoro-count-\(formatter.string(from: Date())).csv"
    }
}
