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

    /// Which grip the pointer is over. An id rather than a `Bool` because every
    /// row's grip is built by the same expression — a shared flag would light
    /// all of them at once.
    @State private var hoveredGrip: UUID?

    /// The row a drag is currently hovering over, highlighted as the place the
    /// dragged category will land.
    @State private var dropTarget: UUID?

    var body: some View {
        // Plain stack plus the system's own drag and drop, after two other
        // mechanisms failed here. A hand-built `DragGesture` worked but
        // flickered: it reordered the array on every crossing, wrote the store
        // each time, and compensated the dragged row's offset by hand against
        // an animation. A `List` with `.onMove` would have handed the whole
        // problem to AppKit, but its reorder does not function in this
        // context — a `List` sized to its contents inside the Settings
        // `ScrollView` — and dragging did nothing at all.
        //
        // `.draggable`/`.dropDestination` depends on neither. Nothing in the
        // list moves while a drag is in flight: the system carries a preview
        // under the pointer, the target row lights up, and the order changes
        // once, on drop. There is no per-frame arithmetic here to get wrong,
        // which is the point.
        VStack(spacing: 6) {
            ForEach(model.settings.categories) { category in
                row(category)
            }
        }
    }

    private func row(_ category: Category) -> some View {
        HStack(spacing: 6) {
            grip(for: category)
            CategorySettingsRow(category: category)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dropTarget == category.id ? palette.accent.opacity(0.16) : .clear)
        }
        .animation(.easeOut(duration: 0.12), value: dropTarget)
        .dropDestination(for: String.self) { items, _ in
            drop(items, onto: category)
        } isTargeted: { over in
            dropTarget = over ? category.id : (dropTarget == category.id ? nil : dropTarget)
        }
        // Without a `List` there is no system reorder action, so VoiceOver gets
        // these. They sit on the row, which already carries the category's
        // name, rather than on the grip, which is a bare glyph.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(category.name)
        .accessibilityAction(named: "Move up") { nudge(category, by: -1) }
        .accessibilityAction(named: "Move down") { nudge(category, by: 1) }
    }

    /// The drag source. Only the grip is draggable, so the name field keeps
    /// drag-to-select and the stepper and remove button are untouched.
    private func grip(for category: Category) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hoveredGrip == category.id ? palette.text : palette.textDim)
            .animation(.easeOut(duration: 0.12), value: hoveredGrip)
            .frame(width: 12, height: 22)
            .contentShape(Rectangle())
            .onHover { inside in
                hoveredGrip = inside ? category.id : (hoveredGrip == category.id ? nil : hoveredGrip)
                // The open hand is the macOS convention for "this can be
                // dragged". The system takes the cursor over during the drag.
                if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            // The id, not the name: names can be edited mid-drag and are not
            // unique until `isCategoryNameAvailable` has had its say.
            .draggable(category.id.uuidString) {
                // What the pointer carries. The row itself is 300pt of
                // controls; its name is what identifies it.
                Text(category.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background { CardBackground(cornerRadius: 8) }
            }
            .help("Drag onto another category to reorder")
            // Decorative: the row it sits on carries the name and the reorder
            // actions, so announcing the glyph too would only add noise.
            .accessibilityHidden(true)
    }

    /// Moves the dragged category into this row's slot.
    ///
    /// Both ends are resolved by id rather than by position: the payload is an
    /// id precisely so that a list which changed under the drag cannot land the
    /// move on the wrong row. Returns false — declining the drop — when the
    /// payload is not one of ours or names the row it is already in.
    private func drop(_ items: [String], onto category: Category) -> Bool {
        dropTarget = nil
        guard let raw = items.first,
              let draggedID = UUID(uuidString: raw),
              let from = model.settings.categories.firstIndex(where: { $0.id == draggedID }),
              let to = model.settings.categories.firstIndex(where: { $0.id == category.id }),
              from != to
        else { return false }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            model.moveCategory(from: from, to: to)
        }
        return true
    }

    /// Animates a one-slot nudge, so a VoiceOver move reads like a drop.
    /// A row at either end stays put — `nudgeCategory` ignores a destination
    /// off the end, so there is no special case here.
    private func nudge(_ category: Category, by delta: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            model.nudgeCategory(id: category.id, by: delta)
        }
    }
}
