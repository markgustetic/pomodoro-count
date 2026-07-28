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

    /// One row's measured height, so the `List` can be sized to its contents.
    @State private var rowHeight: CGFloat = 0

    /// Which grip the pointer is over. An id rather than a `Bool` because every
    /// row's grip is built by the same expression — a shared flag would light
    /// all of them at once.
    @State private var hoveredGrip: UUID?

    /// Vertical padding `listRowInsets` adds to a row, top plus bottom.
    private static let rowInsets: CGFloat = 6

    /// One row's full height including its insets.
    ///
    /// The fallback is the height this row measured at back when it was
    /// hardcoded, and it only applies to the very first frame, before any
    /// measurement has landed. Without it the `List` would be asked for a
    /// height of zero and the rows would vanish — which is exactly what an
    /// earlier attempt at self-sizing this list did.
    private var rowPitch: CGFloat { (rowHeight > 0 ? rowHeight : 26) + Self.rowInsets }

    var body: some View {
        // A `List` rather than a hand-built stack with a `DragGesture`. That
        // was tried: on macOS a `List` is backed by NSTableView, so AppKit
        // drives the reorder natively, while the custom version had to move the
        // array on every crossing and compensate the dragged row's offset by
        // hand. Two rounds of fixes later it still flickered, because each
        // crossing was an array mutation, a store write and an animation racing
        // a hand-computed offset. This is one move, on drop.
        //
        // The grip is what made the `List` usable this time. Its drag starts
        // from any non-interactive part of a row, and this row is a text field,
        // a stepper and a button edge to edge — which is why the affordance was
        // unreachable before. The glyph is the one part of the row that takes
        // no clicks, so it is the part you grab.
        List {
            ForEach(model.settings.categories) { category in
                HStack(spacing: 6) {
                    grip(for: category)
                    CategorySettingsRow(category: category)
                }
                .background {
                    // Every row is the same shape, so they all report the same
                    // height and it does not matter which lands last. Measured
                    // rather than hardcoded: the constant this replaced carried
                    // a comment warning it had to be re-measured by hand
                    // whenever the row's font or padding changed.
                    GeometryReader { geo in
                        // `.task(id:)` rather than `.onChange(of:initial:)`: it
                        // runs after the layout that produced the height, so
                        // writing state here cannot land mid-update.
                        Color.clear.task(id: geo.size.height) { rowHeight = geo.size.height }
                    }
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { model.moveCategories(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Sized to its contents so it does not open a scroller of its own,
        // nested inside the Settings tab's.
        .frame(height: CGFloat(model.settings.categories.count) * rowPitch)
    }

    /// The grab point. Not a `Button` and carrying no gesture of its own: the
    /// `List` handles the drag, and this is here to be the one spot in a row
    /// crowded with controls that a drag can actually start from — and to look
    /// like it.
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
                // dragged". AppKit swaps in the closed one during the drag.
                if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            .help("Drag to reorder")
            // Decorative: the `List` gives VoiceOver its own reorder action on
            // the row, so a second announcement for the glyph is just noise.
            .accessibilityHidden(true)
    }
}
