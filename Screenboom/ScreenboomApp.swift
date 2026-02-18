import SwiftUI
import AVFoundation

@main
struct ScreenboomApp: App {
    private let container: AppContainer
    @State private var project: Project
    @State private var recorderPanelManager = RecorderPanelManager()
    @State private var exportPanelManager = ExportPanelManager()
    @State private var testRecorderFlow: RecorderFlowController?

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
        Self.bootstrapUITestStateIfNeeded(project, store: container.projectStore)
        _project = State(initialValue: project)

        // Recorder harness: embed RecorderBarView directly in main window
        // (NSPanel is outside XCUI accessibility tree)
        if let flow = Self.makeRecorderFlowIfNeeded() {
            _testRecorderFlow = State(initialValue: flow)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let flow = testRecorderFlow {
                    // UI test harness: embed RecorderBarView directly in main window
                    // (NSPanel is outside XCUI accessibility tree)
                    VStack {
                        Spacer()
                        RecorderBarView(
                            flow: flow,
                            onComplete: { _ in },
                            onDismiss: {}
                        )
                        .padding()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .sbPageBackground()
                } else {
                    ContentView(project: project, store: container.projectStore)
                }
            }
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

    // MARK: - UI Test Bootstrap

    private static func bootstrapUITestStateIfNeeded(_ project: Project, store: ProjectStore) {
        guard let mode = ProcessInfo.processInfo.environment["SCREENBOOM_UI_TEST_MODE"] else { return }

        switch mode {
        // ── Welcome Modes ──────────────────────────────────────────────
        case "welcome":
            resetToWelcome(project)

        case "welcome_projects":
            // Welcome screen with synthetic projects in the store grid
            resetToWelcome(project)
            let now = Date()
            store.add(ProjectInfo(
                name: "Demo Recording",
                createdAt: now.addingTimeInterval(-3600),
                lastOpenedAt: now.addingTimeInterval(-600),
                videoWidth: 1920, videoHeight: 1080,
                videoDurationSeconds: 45.2,
                sourceFileName: "demo.mp4"
            ))
            store.add(ProjectInfo(
                name: "Product Tour",
                createdAt: now.addingTimeInterval(-86400),
                lastOpenedAt: now.addingTimeInterval(-7200),
                videoWidth: 2560, videoHeight: 1440,
                videoDurationSeconds: 120.0,
                sourceFileName: "tour.mp4"
            ))
            store.add(ProjectInfo(
                name: "Bug Report",
                createdAt: now.addingTimeInterval(-172800),
                lastOpenedAt: now.addingTimeInterval(-86400),
                videoWidth: 3840, videoHeight: 2160,
                videoDurationSeconds: 8.5,
                sourceFileName: "bug.mp4"
            ))

        // ── Editor Modes (real video pipeline) ────────────────────────
        case "editor", "editor_cursor":
            bootstrapEditorMode(mode, project: project, store: store)

        // ── Editor Modes (synchronous state for deterministic UI testing) ──
        case "editor_selected", "editor_split",
             "editor_cursor_zoom_selected":
            bootstrapEditorFallback(mode, project: project)

        default:
            return
        }
    }

    // MARK: - Recorder Harness

    /// Creates a RecorderFlowController pre-set to a specific state for UI testing.
    /// Returns nil for non-recorder modes.
    private static func makeRecorderFlowIfNeeded() -> RecorderFlowController? {
        guard let mode = ProcessInfo.processInfo.environment["SCREENBOOM_UI_TEST_MODE"] else { return nil }

        switch mode {
        case "recorder_configuring":
            let flow = RecorderFlowController()
            flow._setFlowStateForTesting(.configuring)
            flow.captureMode = .display
            return flow

        case "recorder_recording":
            let flow = RecorderFlowController()
            flow._setFlowStateForTesting(.recording)
            return flow

        case "recorder_countdown":
            let flow = RecorderFlowController()
            flow._setFlowStateForTesting(.countdown(3))
            return flow

        case "recorder_failed":
            let flow = RecorderFlowController()
            flow._setFlowStateForTesting(.failed("Screen recording permission denied"))
            return flow

        default:
            return nil
        }
    }

    // MARK: - Editor Bootstrap (Real Video Pipeline)

    private static func bootstrapEditorMode(_ mode: String, project: Project, store: ProjectStore) {
        // Inject cursor metadata BEFORE video loads — hasCursorData must be true
        // when the tab bar first renders, otherwise cursor/zoom tabs won't appear
        let cursorModes = ["editor_cursor", "editor_cursor_zoom_selected"]
        if cursorModes.contains(mode) {
            injectCursorMetadata(project: project)
        }

        // Generate a real synthetic MP4 through AVAssetWriter (small + cached for speed)
        let videoURL = generateTestVideo(
            width: 640, height: 360,
            duration: 2.0, frameRate: 15
        )

        guard let videoURL else {
            // Fallback: set state directly (same as legacy harness)
            bootstrapEditorFallback(mode, project: project)
            return
        }

        // Route through real DI pipeline: createProject → loadVideo → AVAsset → segments
        project.createProject(url: videoURL, store: store)

        // Post-load setup: runs after loadVideo finishes asynchronously
        let originalCallback = project.onVideoLoaded
        project.onVideoLoaded = { id, size, duration in
            originalCallback?(id, size, duration)
            Self.applyPostLoadState(mode: mode, project: project)
        }
    }

    /// Called after video finishes loading — sets mode-specific state
    private static func applyPostLoadState(mode: String, project: Project) {
        switch mode {
        case "editor":
            // Base editor — split once to get 2 segments
            let midpoint = project.duration.seconds / 2
            project.addSplit(at: midpoint)

        case "editor_selected":
            // Editor with segment pre-selected (shows Disable/Speed controls)
            let midpoint = project.duration.seconds / 2
            project.addSplit(at: midpoint)
            if let firstSeg = project.segments.first {
                project.selectedSegmentId = firstSeg.id
            }

        case "editor_split":
            // Editor with 3 segments (has splitPoints → Remove Split available)
            let dur = project.duration.seconds
            project.addSplit(at: dur * 0.33)
            project.addSplit(at: dur * 0.66)
            if let secondSeg = project.segments.dropFirst().first {
                project.selectedSegmentId = secondSeg.id
            }

        case "editor_cursor":
            // Editor with cursor data — all 6 tabs visible (cursor metadata already injected)
            let midpoint = project.duration.seconds / 2
            project.addSplit(at: midpoint)

        case "editor_cursor_zoom_selected":
            // Editor with cursor data + zoom region pre-selected (cursor metadata already injected)
            let midpoint = project.duration.seconds / 2
            project.addSplit(at: midpoint)
            // Add and select a zoom region
            project.addZoomRegion(at: midpoint)
            if let firstRegion = project.zoomRegions.first {
                project.selectedZoomRegionID = firstRegion.id
                project.selectedSegmentId = nil
            }

        default:
            break
        }
    }

    // MARK: - Synthetic Video Generator

    /// Creates a real MP4 file using AVAssetWriter — routes through the full AVFoundation pipeline.
    /// Cached: generates once per test suite run, reuses across launches for speed.
    private static func generateTestVideo(
        width: Int, height: Int,
        duration: Double, frameRate: Int
    ) -> URL? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenboom-test-video-cached.mp4")

        // Cache: reuse if already generated in this test session
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else { return nil }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        writer.add(writerInput)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(frameRate))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }

            guard let pixelBuffer = createTestFrame(
                width: width, height: height,
                frameIndex: frameIndex, totalFrames: totalFrames
            ) else { continue }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        return writer.status == .completed ? outputURL : nil
    }

    /// Creates a single frame — gradient from dark blue to coral, shifts per frame for visual variety
    private static func createTestFrame(
        width: Int, height: Int,
        frameIndex: Int, totalFrames: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32ARGB, nil, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        let progress = Double(frameIndex) / Double(max(1, totalFrames - 1))

        for y in 0..<height {
            let rowFraction = Double(y) / Double(height)
            // Gradient: dark blue at top → coral at bottom, shifts with time
            let shift = progress * 0.3
            let r = UInt8(min(255, max(0, (0.1 + rowFraction * 0.9 + shift) * 255)))
            let g = UInt8(min(255, max(0, (0.08 + rowFraction * 0.27) * 255)))
            let b = UInt8(min(255, max(0, (0.2 + (1.0 - rowFraction) * 0.5) * 255)))

            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                ptr[offset] = 255     // A
                ptr[offset + 1] = r   // R
                ptr[offset + 2] = g   // G
                ptr[offset + 3] = b   // B
            }
        }

        return buffer
    }

    // MARK: - Cursor Metadata Injection

    private static func injectCursorMetadata(project: Project) {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 640, height: 360),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 360,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.2, x: 100, y: 200, type: .move, button: nil),
                CursorEvent(timestamp: 0.5, x: 150, y: 180, type: .click, button: .left),
                CursorEvent(timestamp: 0.8, x: 300, y: 150, type: .keyDown, button: nil),
                CursorEvent(timestamp: 1.2, x: 400, y: 100, type: .move, button: nil),
                CursorEvent(timestamp: 1.5, x: 320, y: 180, type: .click, button: .left),
                CursorEvent(timestamp: 1.8, x: 200, y: 100, type: .move, button: nil),
            ]
        )
        let metadataURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenboom-uitest-cursor-cached.json")
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL, options: .atomic)
            project.cursorMetadataURL = metadataURL
            project.loadCursorMetadata()
        }
        // Enable auto-zoom so zoom tab shows expanded controls in tests
        project.cursorSettings.autoZoomEnabled = true
    }

    // MARK: - Helpers

    private static func resetToWelcome(_ project: Project) {
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
    }

    /// Legacy fallback: sets state directly without a real video file
    private static func bootstrapEditorFallback(_ mode: String, project: Project) {
        project.currentProjectID = UUID()
        project.videoSize = CGSize(width: 1920, height: 1080)
        project.duration = CMTime(seconds: 12, preferredTimescale: 600)
        project.segments = [
            Segment(startTime: 0, endTime: 6, speed: 1.0, isEnabled: true),
            Segment(startTime: 6, endTime: 12, speed: 1.0, isEnabled: true),
        ]
        project.splitPoints = [6.0]
        project.currentTime = 2
        project.playheadTime = 2
        project.isLoadingProject = false
        project.isClosingProject = false

        switch mode {
        case "editor_selected":
            project.selectedSegmentId = project.segments.first?.id

        case "editor_split":
            project.segments = [
                Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
                Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: true),
                Segment(startTime: 8, endTime: 12, speed: 1.0, isEnabled: true),
            ]
            project.splitPoints = [4.0, 8.0]
            project.selectedSegmentId = project.segments[1].id

        case "editor_cursor", "editor_cursor_zoom_selected":
            injectCursorMetadata(project: project)
            if mode == "editor_cursor_zoom_selected" {
                project.addZoomRegion(at: 3.0)
                if let region = project.zoomRegions.first {
                    project.selectedZoomRegionID = region.id
                    project.selectedSegmentId = nil
                }
            }

        default:
            break
        }
    }
}
