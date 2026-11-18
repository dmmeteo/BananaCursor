//
//  MousecapeCommands.swift
//  Mousecape
//
//  System menu bar commands
//  Removes Edit menu, Cape menu matches context menu
//

import SwiftUI

struct MousecapeCommands: Commands {
    @FocusedValue(\.selectedCape) var selectedCapeBinding: Binding<CursorLibrary?>?

    private var selectedCape: CursorLibrary? {
        selectedCapeBinding?.wrappedValue
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                AppState.shared.currentPage = .settings
                AppState.shared.settingsCategory = .updates
                AppUpdater.shared.checkForUpdates()
            }
            .disabled(!AppUpdater.shared.canCheck)
        }

        // Replace default New Document command
        CommandGroup(replacing: .newItem) {
            Button("New Cape") {
                Task { @MainActor in
                    AppState.shared.createNewCape()
                }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(AppUpdater.shared.isInstalling)

            Button("Import Cape...") {
                Task { @MainActor in
                    AppState.shared.importCape()
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(AppUpdater.shared.isInstalling)

            Divider()

            Button("Open Cape Folder") {
                Task { @MainActor in
                    AppState.shared.openCapeFolder()
                }
            }
        }

        // Save command - Cmd+S (saves in edit mode, exports otherwise)
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                Task { @MainActor in
                    if AppState.shared.isEditing, let cape = AppState.shared.editingCape {
                        AppState.shared.saveCape(cape)
                    } else if let cape = selectedCape {
                        AppState.shared.exportCape(cape)
                    }
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(AppUpdater.shared.isInstalling)
        }

        // Edit menu - Undo/Redo for edit mode
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                Task { @MainActor in
                    AppState.shared.undo()
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!AppState.shared.canUndo || !AppState.shared.isEditing || AppUpdater.shared.isInstalling)

            Button("Redo") {
                Task { @MainActor in
                    AppState.shared.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!AppState.shared.canRedo || !AppState.shared.isEditing || AppUpdater.shared.isInstalling)
        }

        // Keep standard pasteboard/text editing commands for text fields

        // Cape menu - matches context menu
        CommandMenu("Cape") {
            Button("Apply") {
                if let cape = selectedCape {
                    Task { @MainActor in
                        AppState.shared.applyCape(cape)
                    }
                }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(selectedCape == nil || AppUpdater.shared.isInstalling)

            Button("Edit") {
                if let cape = selectedCape {
                    Task { @MainActor in
                        AppState.shared.editCape(cape)
                    }
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(selectedCape == nil || AppUpdater.shared.isInstalling)

            Divider()

            Button("Export...") {
                if let cape = selectedCape {
                    Task { @MainActor in
                        AppState.shared.exportCape(cape)
                    }
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(selectedCape == nil || AppUpdater.shared.isInstalling)

            Button("Show in Finder") {
                if let cape = selectedCape {
                    Task { @MainActor in
                        AppState.shared.showInFinder(cape)
                    }
                }
            }
            .disabled(selectedCape == nil || AppUpdater.shared.isInstalling)

            Divider()

            Button("Reset to Default") {
                Task { @MainActor in
                    AppState.shared.resetToDefault()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(AppUpdater.shared.isInstalling)

            Divider()

            Button("Delete") {
                if let cape = selectedCape {
                    Task { @MainActor in
                        AppState.shared.confirmDeleteCape(cape)
                    }
                }
            }
            .keyboardShortcut(.delete)
            .disabled(selectedCape == nil || AppUpdater.shared.isInstalling)
        }

        // Hide system View menu (toolbar options)
        CommandGroup(replacing: .toolbar) { }

        // Help menu
        CommandGroup(replacing: .help) {
            Button("BananaCursor Help") {
                if let url = URL(string: "https://github.com/dmmeteo/BananaCursor#readme") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Report an Issue") {
                if let url = URL(string: "https://github.com/dmmeteo/BananaCursor/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
