import SwiftUI
import AppKit

/// The Settings page's category editor: the list of categories, the row that
/// edits one, and the forms for adding and removing them. Split out of
/// `SettingsTab`, which was doing this and app preferences in one file.

/// The little form behind "Add category".
///
/// A popover rather than an NSAlert: an alert takes key status away from the
/// menu bar panel, which dismisses the moment it loses focus — you would name a
/// category and come back to a closed panel. A popover stays inside the panel's
/// own window.
///
/// The model is passed in rather than read from the environment. SwiftUI has
/// historically been inconsistent about propagating `@EnvironmentObject` into
/// popover content, and the failure mode is a crash rather than a glitch.
struct AddCategoryForm: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.palette) private var palette

    /// `isCategoryNameAvailable` already rejects empty, whitespace-only, and
    /// anything colliding with a category or the fallback name, so it can drive
    /// the button state directly.
    private var canAdd: Bool { model.isCategoryNameAvailable(name) }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New category")
                .font(.caption)
                .foregroundStyle(palette.textDim)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(add)
                .accessibilityLabel("New category name")

            // Say why Add is disabled rather than leaving a dead button. Stays
            // quiet while the field is still empty — that isn't a mistake yet.
            if !trimmed.isEmpty && !canAdd {
                Text("That name is already taken.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(12)
        .frame(width: 200)
        .onAppear { nameFocused = true }
    }

    private func add() {
        guard model.addCategory(name: name, dailyGoal: 1) else { return }
        name = ""
        isPresented = false
    }
}

/// Confirms removing a category, so a single mis-click on a control the size of
/// a full stop can't quietly take a category off the panel.
///
/// A popover rather than an alert or a `confirmationDialog`, for the reason
/// `AddCategoryForm` gives: either of those takes key status away from the menu
/// bar panel, which dismisses the moment it loses focus — the confirmation
/// would outlive the panel it was confirming something in.
///
/// It says what survives, because "remove" reads far more final than it is:
/// nothing is deleted, the category is archived. Its pomodoros stay in the
/// history, the totals and the CSV export, and adding the same name back
/// reunites it with them.
struct RemoveCategoryConfirmation: View {
    let name: String
    @Binding var isPresented: Bool
    let remove: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remove “\(name)”?")
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("Its pomodoros stay in your history. Adding the name back later reunites it with them.")
                .font(.caption2)
                .foregroundStyle(palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                // Deliberately not `.defaultAction`: Return should not be able
                // to carry out a destructive action the user opened this to
                // think about. Esc cancels; removing takes a click.
                Button("Remove", role: .destructive) {
                    isPresented = false
                    remove()
                }
            }
        }
        .padding(12)
        .frame(width: 230)
    }
}

/// One editable category: rename in place, adjust its goal, or archive it.
struct CategorySettingsRow: View {
    let category: Category
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette
    @State private var draftName: String = ""
    @State private var rejected = false
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(rejected ? Color.red : Color.primary)
                .onSubmit(commit)
                .onAppear { draftName = category.name }
                .accessibilityLabel("Category name")

            Stepper(value: Binding(
                get: { category.dailyGoal },
                set: { goal in
                    guard let i = model.settings.categories.firstIndex(where: { $0.id == category.id })
                    else { return }
                    model.settings.categories[i].dailyGoal = goal
                }
            ), in: 0...20) {
                Text("\(category.dailyGoal)")
                    .font(.caption.monospacedDigit())
            }
            .accessibilityLabel("\(category.name) daily goal")

            Button {
                confirmingRemoval = true
            } label: {
                Image(systemName: "minus.circle")
            }
            // Not `.borderless`: that draws in AppKit's own control grey, which
            // no palette can reach, and it vanished into the Synthwave panel.
            .buttonStyle(HoverTextButtonStyle(emphasis: .destructive))
            .help("Remove — its pomodoros stay in your history")
            .accessibilityLabel("Remove \(category.name)")
            .popover(isPresented: $confirmingRemoval, arrowEdge: .bottom) {
                // `remove` is a closure built here rather than a lookup done
                // inside the popover, for the same reason `AddCategoryForm`
                // takes the model as a parameter: `@EnvironmentObject` does not
                // reliably reach popover content, and it crashes when it misses.
                RemoveCategoryConfirmation(name: category.name,
                                           isPresented: $confirmingRemoval) {
                    model.removeCategory(id: category.id)
                }
                .themed(palette)
            }
        }
    }

    /// Renaming can fail on a collision, so the field snaps back rather than
    /// silently keeping a name the model rejected. On success, the model
    /// stores a trimmed name, so the field is resynced to match — otherwise it
    /// would keep showing untrimmed whitespace the model already discarded.
    private func commit() {
        if model.renameCategory(id: category.id, to: draftName) {
            rejected = false
            draftName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rejected = true
            draftName = category.name
        }
    }
}

/// The fallback bucket's editable name. Its name shares the same uniqueness
/// space as every category's, so it uses the same draft + reject-and-snap-back
/// pattern as `CategorySettingsRow` rather than binding straight to the
/// setting — which would accept a colliding or empty name and rewrite the
/// store on every keystroke.
struct FallbackNameField: View {
    @EnvironmentObject var model: AppModel
    @State private var draftName: String = ""
    @State private var rejected = false

    var body: some View {
        TextField("Name", text: $draftName)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(rejected ? Color.red : Color.primary)
            .onSubmit(commit)
            .onAppear { draftName = model.settings.fallbackName }
            .accessibilityLabel("Fallback category name")
    }

    /// Same rejection contract as `CategorySettingsRow.commit`: on success the
    /// field is resynced to the model's trimmed name; on failure it snaps back
    /// to the name the model still has.
    private func commit() {
        if model.setFallbackName(draftName) {
            rejected = false
            draftName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rejected = true
            draftName = model.settings.fallbackName
        }
    }
}

/// The editable list of the user's categories, reordered by dragging a row's
/// grip handle.
///
/// A plain `VStack` rather than a `List`. `List` synthesises `.onMove`, but its
/// drag starts anywhere in the row, and this row is a text field, a stepper and
/// a button edge to edge — there was nothing to grab, so the reordering it
/// offered was unreachable. A `List` nested in the Settings `ScrollView` also
/// opened a scroller of its own unless given an explicit height, which meant
/// hardcoding a row height and re-measuring it by hand whenever the row changed.
/// The stack drops both problems: the grip is the only drag source, and the row
/// height is measured at layout time.
struct CategoryList: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette

    /// The gap between rows. Half the drag pitch, so it is named rather than
    /// inlined into the `VStack`.
    private static let spacing: CGFloat = 6

    /// One row's measured height. Zero until the first layout has run, which
    /// makes `pitch` zero too — see its doc comment for why that matters.
    @State private var rowHeight: CGFloat = 0
    @State private var drag: DragState?

    /// Which grip the pointer is over. An id rather than a `Bool` because every
    /// row's grip is built by the same function — a shared flag would light all
    /// of them at once.
    @State private var hoveredGrip: UUID?

    /// True only while a drag is actually live. `@GestureState` resets itself
    /// when a gesture is cancelled as well as when it ends, and a cancelled
    /// drag is the one case `onEnded` never reports — so this, not `drag`
    /// itself, is what can be trusted to say whether a gesture is still going.
    @GestureState private var dragIsLive = false

    /// A reorder in progress. `startIndex` is where the row was picked up,
    /// `currentIndex` where it sits now; they diverge as the drag commits moves,
    /// and the gap between them is what keeps the row under the pointer.
    private struct DragState {
        let id: UUID
        let startIndex: Int
        var currentIndex: Int
        var translation: CGFloat = 0
    }

    /// Distance from one row's top edge to the next. Zero, not just `spacing`,
    /// until a row has actually been measured — otherwise an unmeasured list
    /// would report a 6pt pitch and a short drag would fling a row the length
    /// of it. `Reorder.destination` treats a zero pitch as "cannot move yet",
    /// and this is what makes that guard reachable.
    private var pitch: CGFloat { rowHeight > 0 ? rowHeight + Self.spacing : 0 }

    /// Where the dragged row is drawn: the raw translation less the distance
    /// already absorbed by moves it has committed. Without that subtraction the
    /// row would jump a full slot away from the pointer every time it swapped.
    private var visualOffset: CGFloat {
        guard let drag else { return 0 }
        return drag.translation - CGFloat(drag.currentIndex - drag.startIndex) * pitch
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(model.settings.categories.enumerated()), id: \.element.id) { index, category in
                row(category, at: index)
            }
        }
        // The normal path clears `drag` in `onEnded`. This catches the path
        // where `onEnded` never comes: the gesture state going false is
        // SwiftUI telling us the drag is over however it ended. Without it a
        // dead drag's indices survive to steer the next one.
        .onChange(of: dragIsLive) { _, live in
            if !live, drag != nil {
                // Resume here too, not only in `onEnded`. A cancelled drag
                // never reaches `onEnded`, and a suspend left unbalanced would
                // silently stop the app persisting anything at all.
                model.resumeSaves()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = nil }
            }
        }
    }

    private func row(_ category: Category, at index: Int) -> some View {
        let dragging = drag?.id == category.id
        return HStack(spacing: 6) {
            grip(for: category, at: index)
            CategorySettingsRow(category: category)
        }
        .background {
            // Every row is the same shape, so they all report the same height
            // and it does not matter which one lands last. Measured rather than
            // hardcoded: the old `List` needed a fixed row height that had to be
            // re-measured by hand whenever the row's font or padding changed.
            GeometryReader { geo in
                // `.task(id:)` rather than `.onChange(of:initial:)`: it runs
                // after the layout that produced the height, so writing state
                // here cannot land in the middle of a view update.
                Color.clear.task(id: geo.size.height) { rowHeight = geo.size.height }
            }
        }
        .offset(y: dragging ? visualOffset : 0)
        // The dragged row must not animate its own reorder, though its
        // neighbours should. A committed move changes this row's position
        // twice over: its layout slot moves one way and `visualOffset`
        // compensates the other, and the two only cancel if they happen at the
        // same instant. Animating the layout half made them disagree for the
        // length of the spring, so the row lurched a full row and sprang back
        // on every crossing — a drag read as jumping rather than as one
        // movement. Clearing the animation here leaves the neighbours' slide
        // animated and pins this row to the pointer.
        .transaction { if dragging { $0.animation = nil } }
        .scaleEffect(dragging ? 1.02 : 1)
        .shadow(color: .black.opacity(dragging ? 0.28 : 0), radius: 7, y: 3)
        // Lifted clear of its neighbours, so it passes over them rather than
        // under while it is being dragged.
        .zIndex(dragging ? 1 : 0)
        // A drag is the only way to reorder with a mouse, so VoiceOver and the
        // keyboard get these instead. They sit on the row, which already carries
        // the category's name, rather than on the grip, which is a bare glyph.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(category.name)
        .accessibilityAction(named: "Move up") { nudge(category, by: -1) }
        .accessibilityAction(named: "Move down") { nudge(category, by: 1) }
    }

    /// The drag handle. Deliberately not a `Button`: it performs no action when
    /// clicked, and button semantics would promise one. The reorder actions for
    /// VoiceOver and the keyboard live on the row instead.
    private func grip(for category: Category, at index: Int) -> some View {
        let lit = drag?.id == category.id || hoveredGrip == category.id
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(lit ? palette.text : palette.textDim)
            .animation(.easeOut(duration: 0.12), value: hoveredGrip)
            .frame(width: 12, height: 22)
            .contentShape(Rectangle())
            .onHover { inside in
                hoveredGrip = inside ? category.id : (hoveredGrip == category.id ? nil : hoveredGrip)
                // The open hand is the macOS convention for "this can be
                // dragged"; the gesture swaps it for the closed one while a drag
                // is actually running.
                if inside {
                    NSCursor.openHand.set()
                } else if drag == nil {
                    // Only reclaim the cursor when no drag is running. A drag
                    // leaves this 12pt frame almost at once, and the closed hand
                    // set by the gesture has to survive that.
                    NSCursor.arrow.set()
                }
            }
            .gesture(dragGesture(for: category, at: index))
            .help("Drag to reorder")
            // Decorative to VoiceOver: the row it sits on already carries the
            // category's name and the Move up / Move down actions.
            .accessibilityHidden(true)
    }

    /// `minimumDistance: 3` so a stray click on the grip is not a reorder.
    private func dragGesture(for category: Category, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .updating($dragIsLive) { _, live, _ in live = true }
            .onChanged { value in
                // Initialize or reinitialize drag state if this is a fresh drag or a stale
                // drag left behind by an interrupted gesture. `onEnded` is not guaranteed to
                // fire — if the view is torn out of the hierarchy mid-gesture, the drag state
                // persists. Checking identity ensures we start fresh whenever the drag moves
                // to a different row, so stale `startIndex` or `currentIndex` cannot drive a
                // move on the wrong category.
                if drag?.id != category.id {
                    drag = DragState(id: category.id, startIndex: index, currentIndex: index)
                    NSCursor.closedHand.set()
                    // Every crossing moves the array, and each move would
                    // otherwise write the whole store to disk on the main
                    // actor, mid-gesture. One write, when the drag is over.
                    model.suspendSaves()
                }
                guard var state = drag else { return }
                state.translation = value.translation.height

                let destination = Reorder.destination(
                    from: state.startIndex,
                    current: state.currentIndex,
                    translation: state.translation,
                    pitch: pitch,
                    count: model.settings.categories.count)

                if destination != state.currentIndex {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        model.moveCategory(from: state.currentIndex, to: destination)
                    }
                    state.currentIndex = destination
                }
                drag = state
            }
            .onEnded { _ in
                NSCursor.openHand.set()
                model.resumeSaves()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = nil }
            }
    }

    /// Animates a one-slot nudge, so a keyboard move reads the same as a drag.
    /// A row at either end stays put — `nudgeCategory` ignores a destination off
    /// the end, so there is no special case here.
    ///
    /// Declines while a drag is live. A drag holds indices of its own that a
    /// nudge would shift out from under it, leaving it reordering a row the
    /// pointer is no longer on. The two ways of reordering are alternatives, not
    /// things to do at once, and the drag is the one already in progress.
    private func nudge(_ category: Category, by delta: Int) {
        guard drag == nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            model.nudgeCategory(id: category.id, by: delta)
        }
    }
}
