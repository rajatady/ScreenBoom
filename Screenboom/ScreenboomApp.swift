import SwiftUI
import AVFoundation

@main
struct ScreenboomApp: App {
    private let container: AppContainer
    @State private var project: Project
    @State private var recorderPanelManager = RecorderPanelManager()
    @State private var exportPanelManager = ExportPanelManager()

    init() {
        let environment = ProcessInfo.processInfo.environment
        let container: AppContainer
        if environment["XCTestConfigurationFilePath"] != nil || environment["SCREENBOOM_UI_TEST_MODE"] != nil {
            let mode = environment["SCREENBOOM_UI_TEST_MODE"] ?? "default"
            let uiTestStoreDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("screenboom-uitest-store-\(mode)", isDirectory: true)
            try? FileManager.default.removeItem(at: uiTestStoreDirectory)
            container = AppContainer.live(baseDirectory: uiTestStoreDirectory)
        } else {
            container = AppContainer.live()
        }
        self.container = container

        let project = container.makeProject()
        Self.bootstrapUITestStateIfNeeded(project)
        _project = State(initialValue: project)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(project: project, store: container.projectStore)
                .frame(minWidth: 1100, minHeight: 700)
                .environment(recorderPanelManager)
                .environment(exportPanelManager)
                .onAppear {
                    container.projectStore.migrateIfNeeded()
                    let store = container.projectStore
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

    private static func bootstrapUITestStateIfNeeded(_ project: Project) {
        guard let mode = ProcessInfo.processInfo.environment["SCREENBOOM_UI_TEST_MODE"] else { return }

        switch mode {
        case "editor", "editor_cursor":
            project.currentProjectID = UUID()
            project.videoSize = CGSize(width: 1920, height: 1080)
            project.duration = CMTime(seconds: 12, preferredTimescale: 600)
            project.segments = [
                Segment(startTime: 0, endTime: 6, speed: 1.0, isEnabled: true),
                Segment(startTime: 6, endTime: 12, speed: 1.0, isEnabled: true),
            ]
            project.currentTime = 2
            project.playheadTime = 2
            project.isLoadingProject = false
            project.isClosingProject = false

            if mode == "editor_cursor" {
                let metadata = CursorMetadataFile(
                    frameRate: 60,
                    sourceSize: .init(width: 1920, height: 1080),
                    captureOrigin: .init(x: 0, y: 0),
                    displayHeight: 1080,
                    backingScaleFactor: 1.0,
                    events: [
                        CursorEvent(timestamp: 0.5, x: 320, y: 720, type: .move, button: nil),
                        CursorEvent(timestamp: 1.0, x: 360, y: 690, type: .click, button: .left),
                        CursorEvent(timestamp: 1.6, x: 540, y: 500, type: .keyDown, button: nil),
                        CursorEvent(timestamp: 2.2, x: 1280, y: 360, type: .move, button: nil),
                    ]
                )
                let metadataURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("screenboom-uitest-cursor-\(UUID().uuidString).json")
                if let data = try? JSONEncoder().encode(metadata) {
                    try? data.write(to: metadataURL, options: .atomic)
                    project.cursorMetadataURL = metadataURL
                    project.loadCursorMetadata()
                }
            }
        case "welcome":
            project.currentProjectID = nil
            project.sourceURL = nil
            project.asset = nil
            project.player = nil
            project.playerItem = nil
            project.videoSize = .zero
            project.duration = .zero
            project.splitPoints = []
            project.segments = []
            project.selectedSegmentId = nil
            project.zoomRegions = []
            project.selectedZoomRegionID = nil
            project.thumbnails = []
            project.currentTime = 0
            project.playheadTime = 0
            project.isLoadingProject = false
            project.isClosingProject = false
        default:
            return
        }
    }
}
