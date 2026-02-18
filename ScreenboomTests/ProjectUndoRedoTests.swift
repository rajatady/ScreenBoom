import Testing
import AVFoundation
@testable import Screenboom

@MainActor
struct ProjectUndoRedoTests {

    private func makeProject() -> Project {
        let project = Project()
        project.duration = CMTime(seconds: 8, preferredTimescale: 600)
        project.segments = [
            Segment(startTime: 0, endTime: 8, speed: 1.0, isEnabled: true),
        ]
        return project
    }

    @Test func undoRedoRestoresSegmentSpeedAfterBaselineCommit() {
        let project = makeProject()
        let id = project.segments[0].id

        // Establish baseline snapshot so the next edit is undoable.
        project.saveState()
        project.setSpeed(2.5, for: id)
        #expect(abs(project.segments[0].speed - 2.5) < 0.0001)

        project.undo()
        #expect(abs(project.segments[0].speed - 1.0) < 0.0001)

        project.redo()
        #expect(abs(project.segments[0].speed - 2.5) < 0.0001)
    }

    @Test func rapidSpeedEditsBatchIntoSingleUndoStep() {
        let project = makeProject()
        let id = project.segments[0].id

        project.saveState()
        project.setSpeed(1.2, for: id)
        project.setSpeed(1.8, for: id)
        project.setSpeed(3.0, for: id)
        #expect(abs(project.segments[0].speed - 3.0) < 0.0001)

        // Pending batch is committed when undo() is invoked.
        project.undo()
        #expect(abs(project.segments[0].speed - 1.0) < 0.0001)
        #expect(!project.canUndo)
    }

    @Test func undoRedoRestoresAppearanceAndZoomState() {
        let project = makeProject()
        project.videoSize = CGSize(width: 1920, height: 1080)

        project.saveState() // baseline

        project.padding = 120
        project.cornerRadius = 28
        project.showThumbnails = false
        project.cursorSettings.autoZoomEnabled = true
        project.zoomRegions = [
            ZoomRegion(startTime: 1.0, endTime: 3.0, zoomLevel: 2.0, focusX: 600, focusY: 320),
        ]
        project.saveState()

        #expect(project.padding == 120)
        #expect(project.cornerRadius == 28)
        #expect(project.showThumbnails == false)
        #expect(project.cursorSettings.autoZoomEnabled == true)
        #expect(project.zoomRegions.count == 1)

        project.undo()
        #expect(project.padding == 60)
        #expect(project.cornerRadius == 16)
        #expect(project.showThumbnails == true)
        #expect(project.cursorSettings.autoZoomEnabled == false)
        #expect(project.zoomRegions.isEmpty)

        project.redo()
        #expect(project.padding == 120)
        #expect(project.cornerRadius == 28)
        #expect(project.showThumbnails == false)
        #expect(project.cursorSettings.autoZoomEnabled == true)
        #expect(project.zoomRegions.count == 1)
    }
}
