import SwiftUI

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.palette) private var palette
    @State private var addingCategory = false

    var body: some View {
        PanelTabScroller {
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

                // Each duration stepper carries an explicit label and value:
                // left to the Text label, VoiceOver reads the embedded number
                // as the label and then again as the stepper's value.
                Stepper(value: $model.settings.workMinutes, in: 1...180) {
                    Text("Focus: **\(model.settings.workMinutes)** min")
                }
                .accessibilityLabel("Focus duration")
                .accessibilityValue("\(model.settings.workMinutes) minutes")
                Stepper(value: $model.settings.breakMinutes, in: 1...60) {
                    Text("Break: **\(model.settings.breakMinutes)** min")
                }
                .accessibilityLabel("Break duration")
                .accessibilityValue("\(model.settings.breakMinutes) minutes")
                VStack(alignment: .leading, spacing: 2) {
                    Stepper(value: $model.settings.longBreakMinutes, in: 1...60) {
                        Text("Long break: **\(model.settings.longBreakMinutes)** min")
                    }
                    .accessibilityLabel("Long break duration")
                    .accessibilityValue("\(model.settings.longBreakMinutes) minutes")
                    Text("Every 4th focus session earns the long one.")
                        .font(.caption2)
                        .foregroundStyle(palette.textDim)
                }
                Toggle("Auto-start break after focus", isOn: $model.settings.autoStartBreak)
                Toggle("Sound effects", isOn: $model.settings.soundEnabled)

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("End-of-day reminder", isOn: Binding(
                        get: { model.settings.nudgeHour != nil },
                        set: { model.setNudgeHour($0 ? 18 : nil) }
                    ))
                    if let hour = model.settings.nudgeHour {
                        Stepper(value: Binding(
                            get: { hour },
                            set: { model.setNudgeHour($0) }
                        ), in: 0...23) {
                            Text("At **\(hour):00**")
                        }
                        .accessibilityLabel("Reminder hour")
                        .accessibilityValue("\(hour):00")
                        Text("One notification if the day's goal isn't met yet.")
                            .font(.caption2)
                            .foregroundStyle(palette.textDim)
                    }
                }

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
                            // Spelled out, not glyphs: this string doubles as
                            // the spoken hint, and VoiceOver reads ⌃⌥⌘P
                            // unreliably — the same reason spokenDisplay exists.
                            .help("Reset to \(Shortcut.default.spokenDisplay)")
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
                        CategoryList()

                        Button {
                            addingCategory = true
                        } label: {
                            Label("Add category", systemImage: "plus")
                        }
                        .buttonStyle(HoverTextButtonStyle())
                        .font(.caption)
                        .popover(isPresented: $addingCategory, arrowEdge: .bottom) {
                            // A popover is its own window, so it has to be told
                            // the palette's chrome appearance explicitly —
                            // otherwise its light system background lands under
                            // Synthwave's near-white body text.
                            AddCategoryForm(model: model, isPresented: $addingCategory)
                                .themed(palette)
                        }

                        // A sub-option of the category list, so it sits above
                        // the divider that starts the bucket's own section.
                        // Caption2 explanation underneath, matching how the
                        // long-break and shortcut settings carry theirs.
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Follow the category order",
                                   isOn: $model.settings.autoAdvanceTarget)
                            Text("The top category with a goal left is the target, and each new day starts at the top again. Pick one by hand to work there next; pick a finished one to keep going past its goal.")
                                .font(.caption2)
                                .foregroundStyle(palette.textDim)
                        }

                        Divider()

                        // Not a toggle any more: the bucket is where a pomodoro
                        // that belongs to no category goes, so it is always
                        // there. All that is left to set is what to call it and
                        // whether it carries a goal of its own.
                        Text("Everything else")
                            .font(.caption)
                            .foregroundStyle(palette.textDim)
                        HStack(spacing: 6) {
                            // The bucket's name shares the uniqueness space
                            // with every category's, so it goes through the
                            // same committable field rather than binding
                            // straight to the setting — which would accept a
                            // colliding or empty name and rewrite the store
                            // on every keystroke.
                            CommittableNameField(
                                accessibilityLabel: "Fallback category name",
                                current: { model.settings.fallbackName },
                                commit: { model.setFallbackName($0) })
                            Stepper(value: $model.settings.fallbackGoal, in: 0...20) {
                                Text("\(model.settings.fallbackGoal)")
                                    .font(.caption.monospacedDigit())
                            }
                            .accessibilityLabel("Fallback daily goal")
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
        .toggleStyle(.switch)
        .tint(palette.accent)
        .font(.callout)
    }
}
