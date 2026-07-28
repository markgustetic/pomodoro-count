import SwiftUI

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.palette) private var palette
    @State private var addingCategory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Appearance")
                        .font(.caption)
                        .foregroundStyle(palette.textDim)
                    SegmentedControl(
                        items: ThemeChoice.allCases.map { (value: $0, label: $0.rawValue) },
                        selection: $model.settings.theme,
                        accessibilityLabel: "Appearance")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Show count in menu bar", isOn: $model.settings.showsCountInMenuBar)
                    if !model.settings.showsCountInMenuBar {
                        Text("Icon only while idle; the timer still shows during a session.")
                            .font(.caption2)
                            .foregroundStyle(palette.textDim)
                    }
                }

                Stepper(value: $model.settings.workMinutes, in: 1...180) {
                    Text("Focus: **\(model.settings.workMinutes)** min")
                }
                Stepper(value: $model.settings.breakMinutes, in: 1...60) {
                    Text("Break: **\(model.settings.breakMinutes)** min")
                }
                Toggle("Auto-start break after focus", isOn: $model.settings.autoStartBreak)
                Toggle("Sound effects", isOn: $model.settings.soundEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { model.settings.globalShortcutEnabled },
                        set: { model.setGlobalShortcut($0) }
                    )) {
                        Text("Global shortcut")
                    }
                    if model.settings.globalShortcutEnabled {
                        HStack(spacing: 6) {
                            ShortcutRecorder(shortcut: Binding(
                                get: { model.settings.shortcut },
                                set: { model.updateShortcut($0) }
                            ))
                            Button {
                                model.updateShortcut(.default)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(SoftIconButtonStyle(width: 34, height: 26))
                            .help("Reset to ⌃⌥⌘P")
                            .accessibilityLabel("Reset shortcut to control option command P")
                        }
                    }
                    Text("Logs a pomodoro from any app.")
                        .font(.caption2)
                        .foregroundStyle(palette.textDim)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Use categories", isOn: $model.settings.categoriesEnabled)

                    if model.settings.categoriesEnabled {
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

                        Button {
                            addingCategory = true
                        } label: {
                            Label("Add category", systemImage: "plus")
                        }
                        .buttonStyle(HoverTextButtonStyle())
                        .font(.caption)
                        .popover(isPresented: $addingCategory, arrowEdge: .bottom) {
                            AddCategoryForm(model: model, isPresented: $addingCategory)
                        }

                        Divider()

                        Toggle("Fallback category", isOn: $model.settings.usesFallbackBucket)
                        if model.settings.usesFallbackBucket {
                            HStack(spacing: 6) {
                                FallbackNameField()
                                Stepper(value: $model.settings.fallbackGoal, in: 0...20) {
                                    Text("\(model.settings.fallbackGoal)")
                                        .font(.caption.monospacedDigit())
                                }
                                .accessibilityLabel("Fallback daily goal")
                            }
                        } else {
                            Picker("Default", selection: Binding(
                                get: { model.settings.defaultCategoryName ?? "" },
                                set: { model.settings.defaultCategoryName = $0.isEmpty ? nil : $0 }
                            )) {
                                ForEach(model.settings.categories) { category in
                                    Text(category.name).tag(category.name)
                                }
                            }
                            .accessibilityLabel("Default category for untapped pomodoros")
                        }
                    }
                }

                if model.isBundled {
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.launchAtLogin = $0 }
                    ))
                }

                if updater.isSupported {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                        Button("Check for updates now…") { updater.checkForUpdates() }
                            .buttonStyle(HoverTextButtonStyle())
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxHeight: 700)
        .toggleStyle(.switch)
        .tint(palette.accent)
        .font(.callout)
    }
}

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

/// One editable category: rename in place, adjust its goal, or archive it.
struct CategorySettingsRow: View {
    let category: Category
    @EnvironmentObject var model: AppModel
    @State private var draftName: String = ""
    @State private var rejected = false

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
                model.removeCategory(id: category.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove — its pomodoros stay in your history")
            .accessibilityLabel("Remove \(category.name)")
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
