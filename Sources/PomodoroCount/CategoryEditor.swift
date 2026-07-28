import SwiftUI

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

    /// Measured height of one row inside the `List`, including its tamed row
    /// insets — used to size the list to its content instead of letting it
    /// open an internal scroller.
    ///
    /// A hardcoded measurement is unsatisfying, and the obvious replacement does
    /// not work: `.scrollDisabled(true)` plus `.fixedSize(horizontal: false,
    /// vertical: true)` collapses the `List` to zero height and the rows vanish
    /// from Settings entirely. That was tried and reverted. If you change this
    /// row's font, padding, or controls, re-measure this number.
    static let rowHeight: CGFloat = 32

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

/// The editable list of the user's categories.
struct CategoryList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // A List is required for SwiftUI to synthesise the drag-to-reorder
        // affordance for `.onMove` — a ForEach in a plain VStack never gets
        // one. It's given an explicit height sized to its row count so it
        // doesn't open its own internal scroller nested inside the tab's
        // outer ScrollView.
        List {
            ForEach(model.settings.categories) { category in
                CategorySettingsRow(category: category)
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { model.moveCategories(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(model.settings.categories.count) * CategorySettingsRow.rowHeight)
    }
}
