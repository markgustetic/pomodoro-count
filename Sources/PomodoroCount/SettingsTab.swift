import SwiftUI
import AppKit

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.palette) private var palette

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
                        .frame(height: CGFloat(model.settings.categories.count) * Self.categoryRowHeight)

                        Button {
                            addCategory()
                        } label: {
                            Label("Add category", systemImage: "plus")
                        }
                        .buttonStyle(HoverTextButtonStyle())
                        .font(.caption)

                        Divider()

                        Toggle("Fallback category", isOn: $model.settings.usesFallbackBucket)
                        if model.settings.usesFallbackBucket {
                            HStack(spacing: 6) {
                                TextField("Name", text: $model.settings.fallbackName)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Fallback category name")
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
        .frame(maxHeight: 620)
        .toggleStyle(.switch)
        .tint(palette.accent)
        .font(.callout)
    }

    /// Measured height of one `CategorySettingsRow` inside the `List`, including
    /// its tamed row insets — used to size the list to its content instead of
    /// letting it open an internal scroller.
    private static let categoryRowHeight: CGFloat = 32

    /// Names a new category "Category 2", "Category 3"… so adding never fails
    /// on a collision the user did not choose.
    private func addCategory() {
        var index = model.settings.categories.count + 1
        while !model.addCategory(name: "Category \(index)", dailyGoal: 1) {
            index += 1
            if index > 99 { return }
        }
    }
}

/// One editable category: rename in place, adjust its goal, or archive it.
struct CategorySettingsRow: View {
    let category: Category
    @EnvironmentObject var model: AppModel
    @State private var draftName: String = ""
    @State private var rejected = false

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
