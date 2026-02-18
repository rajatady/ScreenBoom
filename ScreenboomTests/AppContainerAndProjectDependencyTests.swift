import Testing
import Foundation
import AVFoundation
import CoreGraphics
@testable import Screenboom

@MainActor
struct AppContainerAndProjectDependencyTests {

    private final class CapturingStateStore: ProjectStateStoreProtocol {
        var stateToLoad: SavedState?
        var loadedURLs: [URL] = []
        var savedStates: [SavedState] = []
        var savedURLs: [URL] = []

        func loadState(from url: URL) -> SavedState? {
            loadedURLs.append(url)
            return stateToLoad
        }

        func saveState(_ state: SavedState, to url: URL) {
            savedStates.append(state)
            savedURLs.append(url)
        }
    }

    private final class CapturingExportService: ExportServiceProtocol {
        var invocationCount = 0
        var lastOutputURL: URL?
        var lastSourceSize: CGSize?
        var lastExportSize: CGSize?
        var lastSegmentCount: Int = 0

        func export(
            asset: AVAsset,
            enabledSegments: [Segment],
            sourceSize: CGSize,
            exportSettings: FrameRenderer.Settings,
            cursorOverlayState: CursorOverlayState?,
            outputURL: URL,
            progress: @escaping @Sendable (Double) -> Void
        ) async throws {
            invocationCount += 1
            lastOutputURL = outputURL
            lastSourceSize = sourceSize
            lastExportSize = exportSettings.outputSize
            lastSegmentCount = enabledSegments.count
            progress(0.4)
            progress(1.0)
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSavedState(sourceURLPath: String? = nil) -> SavedState {
        SavedState(
            sourceURLBookmark: nil,
            sourceURLPath: sourceURLPath,
            splitPoints: [],
            segmentStates: [
                SavedState.SavedSegment(startTime: 0, endTime: 5, speed: 1, isEnabled: true),
            ],
            gradientColor1: [0.08, 0.08, 0.12],
            gradientColor2: [0.18, 0.12, 0.28],
            padding: 60,
            cornerRadius: 16,
            shadowRadius: 30,
            shadowOpacity: 0.5,
            outputWidth: 1920,
            outputHeight: 1080,
            playheadTime: 1,
            showThumbnails: true,
            backgroundStyleJSON: nil,
            frameStyleJSON: nil,
            cursorEnabled: nil,
            cursorStyle: nil,
            cursorSize: nil,
            clickEffectEnabled: nil,
            clickEffectColor: nil,
            clickEffectMaxRadius: nil,
            clickEffectDuration: nil,
            autoZoomEnabled: nil,
            autoZoomLevel: nil,
            autoZoomSensitivity: nil,
            zoomRegions: nil
        )
    }

    @Test func appContainerMakeProjectUsesInjectedDependencies() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateStore = CapturingStateStore()
        let exportService = CapturingExportService()
        let deps = ProjectDependencies(stateStore: stateStore, exportService: exportService)
        let store = ProjectStore(baseDirectory: tempDir)
        let container = AppContainer(projectStore: store, projectDependencies: deps)

        let project = container.makeProject()
        let projectID = UUID()
        project.currentProjectID = projectID
        project.store = store

        project.closeProject()

        #expect(stateStore.savedURLs.first == store.stateFileURL(for: projectID))
    }

    @Test func loadProjectReadsStateThroughInjectedStateStore() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateStore = CapturingStateStore()
        stateStore.stateToLoad = makeSavedState()
        let deps = ProjectDependencies(stateStore: stateStore, exportService: CapturingExportService())

        let store = ProjectStore(baseDirectory: tempDir)
        let info = ProjectInfo(name: "Fixture")
        store.add(info)

        let project = Project(dependencies: deps)
        project.loadProject(info: info, store: store)

        #expect(stateStore.loadedURLs == [store.stateFileURL(for: info.id)])
    }

    @Test func runExportDelegatesToInjectedExportService() async {
        let stateStore = CapturingStateStore()
        let exportService = CapturingExportService()
        let deps = ProjectDependencies(stateStore: stateStore, exportService: exportService)

        let project = Project(dependencies: deps)
        project.asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/nonexistent.mp4"))
        project.videoSize = CGSize(width: 1920, height: 1080)
        project.outputWidth = 1280
        project.outputHeight = 720
        project.segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: false),
        ]

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("screenboom-test-\(UUID().uuidString).mp4")
        await project.runExport(to: outputURL)

        #expect(exportService.invocationCount == 1)
        #expect(exportService.lastOutputURL == outputURL)
        #expect(exportService.lastSourceSize == CGSize(width: 1920, height: 1080))
        #expect(exportService.lastExportSize == CGSize(width: 1280, height: 720))
        #expect(exportService.lastSegmentCount == 1) // disabled segments filtered out in Project
        #expect(project.exportProgress == 1.0)
        #expect(!project.isExporting)
    }

    @Test func runExportSkipsServiceWhenNoEnabledSegments() async {
        let exportService = CapturingExportService()
        let deps = ProjectDependencies(stateStore: CapturingStateStore(), exportService: exportService)
        let project = Project(dependencies: deps)
        project.asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/nonexistent.mp4"))
        project.segments = [
            Segment(startTime: 0, endTime: 3, speed: 1.0, isEnabled: false),
        ]

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("screenboom-test-\(UUID().uuidString).mp4")
        await project.runExport(to: outputURL)

        #expect(exportService.invocationCount == 0)
        #expect(!project.isExporting)
    }
}
