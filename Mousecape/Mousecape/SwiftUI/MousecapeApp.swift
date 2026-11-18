//
//  MousecapeApp.swift
//  Mousecape
//
//  SwiftUI App entry point for macOS 15+
//

import SwiftUI

@main
struct BananaCursorApp: App {
    @State private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("BananaCursor") {
            AppearanceWrapper {
                ContentView()
                    .environment(appState)
            }
            .onAppear {
                configureWindowAppearance()
            }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            MousecapeCommands()
        }
    }

    private func configureWindowAppearance() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }

            // Make titlebar transparent for cleaner look
            window.titlebarAppearsTransparent = true

            // Use opaque window background for macOS 15 (Liquid Glass transparency was for macOS 26)
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor

            // Disable fullscreen (green) button
            window.collectionBehavior.remove(.fullScreenPrimary)
            if let zoomButton = window.standardWindowButton(.zoomButton) {
                zoomButton.isEnabled = false
            }

            // Set up window delegate for close confirmation
            appDelegate.setupWindowDelegate(for: window, appState: appState)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegate: WindowDelegate?

    @MainActor
    func setupWindowDelegate(for window: NSWindow, appState: AppState) {
        windowDelegate = WindowDelegate(appState: appState)
        window.delegate = windowDelegate
        windowDelegate?.startObservingDirtyState()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdater.shared.start()
        // Apply last cape on launch if enabled
        let applyLastCapeOnLaunch = UserDefaults.standard.bool(forKey: "applyLastCapeOnLaunch")
        // Default to true if never set
        if UserDefaults.standard.object(forKey: "applyLastCapeOnLaunch") == nil {
            UserDefaults.standard.set(true, forKey: "applyLastCapeOnLaunch")
        }

        if applyLastCapeOnLaunch || UserDefaults.standard.object(forKey: "applyLastCapeOnLaunch") == nil {
            // Get last applied cape identifier from preferences
            if let lastCapeIdentifier = UserDefaults.standard.string(forKey: "lastAppliedCapeIdentifier") {
                Task { @MainActor in
                    let appState = AppState.shared
                    if let cape = appState.capes.first(where: { $0.identifier == lastCapeIdentifier }) {
                        appState.applyCape(cape)
                    }
                }
            }
        }
    }

    // Quit app when last window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let updater = AppUpdater.shared
        guard updater.canTerminate else { return .terminateCancel }
        if updater.isInstalling { return .terminateNow }
        return AppState.shared.confirmLeavingEditor() ? .terminateNow : .terminateCancel
    }
}

// MARK: - Window Delegate (handles close confirmation)

@MainActor
class WindowDelegate: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var timer: Timer?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func startObservingDirtyState() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDocumentEdited()
            }
        }
    }

    private func updateDocumentEdited() {
        guard let window = NSApp.windows.first else { return }
        // Use manual hasUnsavedChanges instead of ObjC isDirty
        let isDirty = appState.isEditing && appState.hasUnsavedChanges
        if window.isDocumentEdited != isDirty {
            window.isDocumentEdited = isDirty
        }
    }

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            AppUpdater.shared.canTerminate && appState.confirmLeavingEditor()
        }
    }
}

struct AppearanceWrapper<Content: View>: View {
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @ViewBuilder let content: Content

    var body: some View {
        content
            .preferredColorScheme(effectiveColorScheme)
            .onChange(of: appearanceMode, initial: true) { _, newValue in
                updateAppAppearance(newValue)
            }
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private func updateAppAppearance(_ mode: Int) {
        switch mode {
        case 1:
            NSApp.appearance = NSAppearance(named: .aqua)
        case 2:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}

// MARK: - Content View (Root)

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        MainView()
            .disabled(AppUpdater.shared.isInstalling)
            // Error alert
            .alert("Error", isPresented: $appState.showError) {
                Button("OK") {
                    appState.showError = false
                }
            } message: {
                if let error = appState.lastError {
                    Text(error.localizedDescription)
                }
            }
    }
}

// MARK: - FocusedValues for Menu Commands

extension FocusedValues {
    struct SelectedCapeKey: FocusedValueKey {
        typealias Value = Binding<CursorLibrary?>
    }

    var selectedCape: Binding<CursorLibrary?>? {
        get { self[SelectedCapeKey.self] }
        set { self[SelectedCapeKey.self] = newValue }
    }
}
