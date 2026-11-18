//
//  SettingsView.swift
//  Mousecape
//
//  Settings view with left sidebar navigation
//  Integrated into main window via page switcher
//

import SwiftUI

struct SettingsView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left sidebar: Category list
            List(SettingsCategory.allCases, selection: $appState.settingsCategory) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            // Right: Settings content based on selected category
            settingsContent
                .scrollContentBackground(.hidden)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    appState.currentPage = .home
                }) {
                    Image(systemName: "checkmark")
                }
                .help("Done")
            }
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch appState.settingsCategory {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .updates:
            UpdateSettingsView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("applyLastCapeOnLaunch") private var applyLastCapeOnLaunch = true
    @AppStorage("doubleClickAction") private var doubleClickAction = 0
    @State private var scale: Double = 1.0

    /// The key used by ObjC code for cursor scale
    private static let cursorScaleKey = "MCCursorScale"
    private static let preferenceDomain = MCPreferencesDomain

    var body: some View {
        Form {
            HelperToolSettingsView()

            Section("Startup") {
                Toggle("Apply Last Cape on Launch", isOn: $applyLastCapeOnLaunch)
            }

            Section("Double-click Action") {
                Picker("When double-clicking a Cape", selection: $doubleClickAction) {
                    Text("Apply Cape").tag(0)
                    Text("Edit Cape").tag(1)
                    Text("Do Nothing").tag(2)
                }
            }

            Section("Cursor Scale") {
                VStack(alignment: .leading) {
                    Text("Global Scale: \(scale, specifier: "%.1f")x")
                    Slider(value: Binding(
                        get: { scale },
                        set: { newValue in
                            scale = newValue
                            saveCursorScale(newValue)
                            _ = setCursorScale(Float(newValue))
                        }
                    ), in: 0.5...2.0, step: 0.1) {
                        Text("Scale")
                    } minimumValueLabel: {
                        Text("0.5x")
                    } maximumValueLabel: {
                        Text("2.0x")
                    }

                    Text("Scale changes are applied immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("General")
        .onAppear {
            loadCursorScale()
        }
    }

    /// Load cursor scale from CFPreferences (same as ObjC code)
    private func loadCursorScale() {
        if let value = CFPreferencesCopyAppValue(Self.cursorScaleKey as CFString, Self.preferenceDomain as CFString) as? Double {
            scale = value
        } else {
            scale = Double(cursorScale())
        }
    }

    /// Save cursor scale to CFPreferences (same as ObjC code)
    private func saveCursorScale(_ value: Double) {
        CFPreferencesSetAppValue(
            Self.cursorScaleKey as CFString,
            value as CFNumber,
            Self.preferenceDomain as CFString
        )
        CFPreferencesAppSynchronize(Self.preferenceDomain as CFString)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @AppStorage("showPreviewAnimations") private var showPreviewAnimations = true
    @AppStorage("showAuthorInfo") private var showAuthorInfo = true
    @AppStorage("previewGridColumns") private var previewGridColumns = 0

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.radioGroup)
            }

            Section("List Display") {
                Toggle("Show Cursor Preview Animations", isOn: $showPreviewAnimations)
                Toggle("Show Cape Author Info", isOn: $showAuthorInfo)
            }

            Section("Preview Panel") {
                Picker("Preview Grid Columns", selection: $previewGridColumns) {
                    Text("Auto (based on window size)").tag(0)
                    Text("4 columns").tag(4)
                    Text("6 columns").tag(6)
                    Text("8 columns").tag(8)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Appearance")
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @State private var showResetConfirmation = false
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Cape Folder") {
                    Text("~/Library/Application Support/\(MCCapeDirectoryName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Show in Finder") {
                    appState.openCapeFolder()
                }
            }

            Section("Reset") {
                Button("Restore Default Settings", role: .destructive) {
                    showResetConfirmation = true
                }
                .confirmationDialog(
                    "Restore Default Settings",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Restore Default Settings", role: .destructive) {
                        resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will reset all settings to their default values. This action cannot be undone.")
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("BananaCursor v\(version) (\(build))")
                    } else {
                        Text("BananaCursor")
                    }
                }
                LabeledContent("System Requirements") {
                    Text("macOS 15+")
                }
                LabeledContent("Original Author") {
                    Text("\u{00A9} 2014-2025 Alex Zielenski")
                }
                LabeledContent("SwiftUI Redesign") {
                    Text("\u{00A9} 2025 sdmj76")
                }

                HStack {
                    Button("GitHub") {
                        if let url = URL(string: "https://github.com/dmmeteo/BananaCursor") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Report Issue") {
                        if let url = URL(string: "https://github.com/dmmeteo/BananaCursor/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Advanced")
    }

    private func resetToDefaults() {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
    }

}

struct UpdateSettingsView: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section("Updates") {
                Text(updater.status)
                    .textSelection(.enabled)
                if updater.isInstalling || updater.state == .checking {
                    ProgressView().controlSize(.small)
                }
                Toggle("Automatic update checks", isOn: $updater.automaticChecks)
                Text("Checks once a day while the app is open. Updates download only when you choose Install and Restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Check for Updates") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                    if updater.canInstall {
                        Button("Install and Restart") { updater.installAndRestart() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppState.shared)
        .frame(width: 600, height: 500)
}
