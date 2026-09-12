import SwiftUI

struct AppCommands: Commands {
    @Bindable var commandCenter: AppCommandCenter

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                commandCenter.perform(.newProject)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Request") {
                commandCenter.perform(.newRequest)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Request") {
            Button(commandCenter.workspace?.executionState == .running ? "Stop" : "Send") {
                if commandCenter.workspace?.executionState == .running {
                    commandCenter.perform(.cancelRequest)
                } else {
                    commandCenter.perform(.sendRequest)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(commandCenter.selectedRequestID == nil)

            Button("Cancel") {
                commandCenter.perform(.cancelRequest)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(commandCenter.workspace?.executionState != .running)

            Divider()

            Button("Duplicate Request") {
                commandCenter.perform(.duplicateRequest)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(commandCenter.selectedRequestID == nil)

            Button("Rename Request") {
                commandCenter.perform(.renameRequest)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(commandCenter.selectedRequestID == nil)

            Button("Format JSON Body") {
                commandCenter.perform(.formatJSON)
            }
            .disabled(commandCenter.selectedRequestID == nil)

            Button("Focus URL") {
                commandCenter.perform(.focusURL)
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") {
                commandCenter.perform(.toggleInspector)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
