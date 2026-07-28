import SwiftUI
import AppKit

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.palette) private var palette

    var body: some View {
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
        .toggleStyle(.switch)
        .tint(palette.accent)
        .font(.callout)
    }
}
