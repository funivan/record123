import SwiftUI

struct Record123App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Record123", id: "main") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") { state.toggleRecording() }.keyboardShortcut("n")
                Button("Back to Recordings") { state.closeEditor() }.keyboardShortcut("[")
                    .disabled(state.editor == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close and Quit") { NSApp.terminate(nil) }.keyboardShortcut("w")
                Button("Close and Quit (Ctrl)") { NSApp.terminate(nil) }.keyboardShortcut("w", modifiers: .control)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { state.editor?.undo() }.keyboardShortcut("z")
                Button("Redo") { state.editor?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .importExport) {
                Button("Export…") { state.editor?.runExportPanel() }.keyboardShortcut("e")
                    .disabled(state.editor == nil)
            }
        }

        Settings {
            SettingsView().environmentObject(state)
        }

        MenuBarExtra {
            MenuContent().environmentObject(state)
        } label: {
            MenuLabel().environmentObject(state)
        }
    }
}

struct MenuLabel: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        switch state.phase {
        case .recording: Label(formatTime(state.elapsed), systemImage: "record.circle.fill")
        case .countdown(let n): Label("\(n)", systemImage: "timer")
        case .saving: Label("Saving", systemImage: "hourglass")
        case .idle: Image(systemName: "record.circle")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(menuTitle) { state.toggleRecording() }
            .disabled(state.phase == .saving)
        Button("Open Record123") {
            openWindow(id: "main")
            state.showMainWindow()
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }

    private var menuTitle: String {
        switch state.phase {
        case .idle: return "Start recording"
        case .countdown: return "Cancel countdown"
        case .recording: return "Stop recording"
        case .saving: return "Saving…"
        }
    }
}
