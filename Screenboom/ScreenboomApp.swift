import SwiftUI

@main
struct ScreenboomApp: App {
    @State private var project = Project()

    var body: some Scene {
        WindowGroup {
            ContentView(project: project)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { project.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!project.canUndo)
                Button("Redo") { project.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!project.canRedo)
            }
        }
    }
}
