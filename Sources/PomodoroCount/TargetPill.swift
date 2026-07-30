import AppKit

/// What the Focus tab's session-target pill says, shortened to what it can
/// actually draw.
///
/// Pure and total over its inputs — the same shape as `Reorder.destination`,
/// `CategoryAdvance.next` and `PanelMetrics.tabHeightCap` — because the pill
/// cannot be constrained where it is drawn. `.menuStyle(.borderlessButton)`
/// puts the label inside an `NSPopUpButton`, which ignores SwiftUI frames on
/// its content just as it drops Shapes and overrides `foregroundStyle` (all
/// three are noted at the call site in `RootView`). `.lineLimit` and
/// `.truncationMode` therefore never get a width to truncate against, and a
/// long category name drew the pill — and the card holding it — clean off the
/// panel's fixed 300pt edge. So the string is shortened *before* it reaches the
/// label, which is the one thing NSPopUpButton cannot undo.
///
/// The budget is measured rather than counted in characters: "pinned to " is
/// wider than "towards ", and "Machine learning" is wider than "iiiiiiiiiiiiiiii"
/// at the same length, so a character budget generous enough for the widest
/// name would have to truncate ordinary ones far too early.
enum TargetPill {

    /// The pill's own text, as SwiftUI's `.font(.caption)` draws it on macOS.
    ///
    /// Measured, not assumed: across labels from 73pt to 222pt wide, the pill
    /// the panel actually lays out came out a flat 24.2–24.9pt wider than this
    /// font reports for its string. A constant offset over a 150pt range is
    /// what identifies the font — a wrong one would drift with length rather
    /// than sit still. Computed rather than stored so nothing holds an AppKit
    /// object in global state.
    static var font: NSFont { NSFont.preferredFont(forTextStyle: .caption1) }

    /// What `NSPopUpButton` draws around the label — the chevron, the control's
    /// own padding, and its habit of rounding its width up to whole points.
    ///
    /// Measure it against the real panel, not against a hand-built Menu with
    /// the same modifiers: the stand-in came out 19.3pt and the panel 24.9,
    /// and a constant five points light is a pill that overflows only for the
    /// widest names — the exact bug this file exists to end.
    /// `TargetPillTests` re-measures it on every run.
    static let chrome: CGFloat = 25

    /// `RootView`'s `.frame(width: 300)`, its `.padding(14)`, and the focus
    /// card's `.padding(.horizontal, 14)` — everything between the pill and the
    /// panel's edge. Kept as three named numbers rather than one 244 so a
    /// change to the panel's own geometry has an obvious place to land.
    static let panelWidth: CGFloat = 300
    static let panelPadding: CGFloat = 14
    static let cardPadding: CGFloat = 14

    /// The widest the pill may draw before the card it sits in outgrows the
    /// panel and clips at both edges.
    static let maxWidth: CGFloat = panelWidth - 2 * (panelPadding + cardPadding)

    /// How wide `text` draws in the pill's font, chrome excluded.
    static func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// `prefix` followed by as much of `name` as fits in `maxWidth`.
    ///
    /// The promise — "towards " or "pinned to " — is never what gets cut. It is
    /// the whole difference between the two kinds of hand pick (see
    /// `AppModel.sessionTargetDescription`), so eating it to save a few
    /// characters of a name would drop the one thing the pill says that the
    /// menu below it doesn't. Only the name shortens, tail-first with an
    /// ellipsis, which is what the dead `.truncationMode(.tail)` promised.
    ///
    /// The full name is still reachable: VoiceOver reads the untruncated
    /// `sessionTargetDescription`, and the menu this labels lists every
    /// category in full.
    static func label(prefix: String, name: String, maxWidth: CGFloat = Self.maxWidth) -> String {
        let budget = maxWidth - chrome
        let whole = prefix + name
        guard width(whole) > budget else { return whole }

        // Binary search the longest head of `name` that still fits once its
        // ellipsis is on. A character never narrows the line, so "fits" flips
        // to "doesn't" exactly once and a search finds that crossing in about
        // log2(n) measurements instead of one per character — a pasted-in name
        // thousands of characters long would otherwise cost thousands of them,
        // every time the pill redraws.
        let characters = Array(name)
        var fits = 0, fails = characters.count
        while fails - fits > 1 {
            let mid = (fits + fails) / 2
            if width(shortened(prefix, characters, keeping: mid)) <= budget {
                fits = mid
            } else {
                fails = mid
            }
        }
        // `fits` may be 0, leaving just the promise and an ellipsis. That is the
        // floor rather than a failure: a pill too narrow for any of the name
        // still says which kind of target is in force.
        return shortened(prefix, characters, keeping: fits)
    }

    /// The first `keeping` characters of the name, with its ellipsis.
    ///
    /// Trailing whitespace goes first, so a cut landing after a word reads
    /// "Machine learning…" rather than "Machine learning …". Cutting by
    /// `Character` rather than by unicode scalar or byte is what keeps an emoji
    /// or a combining accent in a category name from being split in half.
    private static func shortened(_ prefix: String,
                                  _ characters: [Character],
                                  keeping: Int) -> String {
        let head = String(characters.prefix(keeping))
            .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return prefix + head + "…"
    }
}
