import SwiftUI

@main
struct ScreenboomApp: App {
    @State private var project = Project()
    @State private var projectStore = ProjectStore()
    @State private var recorderPanelManager = RecorderPanelManager()
    @State private var exportPanelManager = ExportPanelManager()

    var body: some Scene {
        WindowGroup {
            ContentView(project: project, store: projectStore)
                .frame(minWidth: 1100, minHeight: 700)
                .environment(recorderPanelManager)
                .environment(exportPanelManager)
                .onAppear {
                    projectStore.migrateIfNeeded()
                    let store = projectStore
                    project.onVideoLoaded = { id, size, duration in
                        store.update(id) { info in
                            info.videoWidth = Int(size.width)
                            info.videoHeight = Int(size.height)
                            info.videoDurationSeconds = duration
                        }
                    }
                }
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
