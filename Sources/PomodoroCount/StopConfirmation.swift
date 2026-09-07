import SwiftUI

/// The words behind the "are you sure?" that guards the stop and cup buttons.
///
/// Pure, and switched exhaustively on `Phase`, so that a fifth phase fails a
/// test (and the compiler) instead of the panel quietly asking the wrong
/// question — the same reason `StatusIcon.glyph` lives outside its view.
enum StopConfirmation {
    struct Prompt: Equatable {
        let title: String
        let note: String
        /// The confirm button's label. Says what happens, never "OK".
        let verb: String
    }

    /// What the stop button asks. The note names what the press costs, because
    /// that is what the user is hesitating over — and it differs: an armed or
    /// running break has a logged session behind it, a focus session has none.
    static func prompt(phase: Phase) -> Prompt {
        switch phase {
        case .breakReady:
            return Prompt(title: "Skip the break?",
                          note: "The session is already logged.",
                          verb: "Skip")
        case .work:
            return Prompt(title: "Abandon this session?",
                          note: "Nothing is logged.",
                          verb: "Abandon")
        case .breakTime:
            return Prompt(title: "Cut the break short?",
                          note: "Back to idle; the session stays logged.",
                          verb: "Stop")
        case .idle:
            // Unreachable from the panel — the stop button is disabled while
            // idle — but a total function beats an optional the view has to
            // unwrap. Honest wording in case that ever changes.
            return Prompt(title: "Reset the timer?",
                          note: "Nothing is running.",
                          verb: "Reset")
        }
    }

    /// What the cup button asks mid-session, where it logs the session as done
    /// before starting the break — so the thing to think twice about is a
    /// pomodoro on the count that wasn't finished, not one lost.
    static let restNowPrompt = Prompt(title: "End the session early?",
                                      note: "It counts as done, and the break starts.",
                                      verb: "Log and rest")

    /// Whether the cup press needs confirming. Only a mid-session press changes
    /// the count; from idle the cup just starts a break, and a prompt there
    /// would be friction guarding nothing. (`offersManualBreak` already hides
    /// the cup in the two break phases.)
    static func restNowAsks(phase: Phase) -> Bool {
        phase == .work
    }
}

/// The popover the stop and cup buttons open before acting.
///
/// A popover rather than an alert or a `confirmationDialog`, for the reason
/// `RemoveCategoryConfirmation` gives: either would take key status from the
/// non-activating panel and dismiss the very panel it was confirming in. Takes
/// closures rather than the model because `@EnvironmentObject` does not reliably
/// reach popover content, and fails by crashing.
struct StopConfirmationView: View {
    let prompt: StopConfirmation.Prompt
    @Binding var isPresented: Bool
    let confirm: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.title)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(prompt.note)
                .font(.caption2)
                .foregroundStyle(palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                // Deliberately not `.defaultAction`: Return must not be able
                // to throw away the session the user opened this to think
                // about. Esc cancels; confirming takes a click.
                Button(prompt.verb, role: .destructive) {
                    isPresented = false
                    confirm()
                }
            }
        }
        .padding(12)
        .frame(width: 230)
        // Paints its own background and text colour: `.themed(palette)` swaps
        // the environment's `colorScheme` but cannot repaint the NSPopover's
        // material, and `RootView`'s ambient foreground does not survive the
        // crossing into the popover's separate window. Same as the other
        // confirmations — see `RemoveCategoryConfirmation`.
        .foregroundStyle(palette.text)
        .background { if palette.paintsBackground { palette.background } }
    }
}
