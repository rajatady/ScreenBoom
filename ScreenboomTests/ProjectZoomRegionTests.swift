import Testing
import AVFoundation
@testable import Screenboom

@MainActor
struct ProjectZoomRegionTests {

    private func makeProject(duration: Double = 12, size: CGSize = CGSize(width: 1920, height: 1080)) -> Project {
        let project = Project()
        project.duration = CMTime(seconds: duration, preferredTimescale: 600)
        project.videoSize = size
        project.segments = [
            Segment(startTime: 0, endTime: duration, speed: 1.0, isEnabled: true),
        ]
        return project
    }

    @Test func addZoomRegionSelectsRegionAndEnablesAutoZoom() {
        let project = makeProject(duration: 10)
        project.cursorSettings.autoZoomEnabled = false
        project.cursorSettings.autoZoomLevel = 1.6

        project.addZoomRegion(at: 5.0)

        #expect(project.zoomRegions.count == 1)
        let region = project.zoomRegions[0]
        #expect(project.selectedZoomRegionID == region.id)
        #expect(project.cursorSettings.autoZoomEnabled)
        #expect(abs(region.startTime - 4.0) < 0.0001)
        #expect(abs(region.endTime - 6.0) < 0.0001)
        #expect(abs(region.focusX - 960.0) < 0.0001)
        #expect(abs(region.focusY - 540.0) < 0.0001)
        #expect(abs(project.playheadTime - 5.0) < 0.0001)
    }

    @Test func setZoomRegionLevelClampsToSupportedRange() {
        let project = makeProject()
        project.addZoomRegion(at: 3.0)
        let id = project.zoomRegions[0].id

        project.setZoomRegionLevel(10.0, for: id)
        #expect(abs(project.zoomRegions[0].zoomLevel - 4.0) < 0.0001)

        project.setZoomRegionLevel(1.01, for: id)
        #expect(abs(project.zoomRegions[0].zoomLevel - 1.1) < 0.0001)
    }

    @Test func setZoomRegionFocusClampsToVisibleBounds() {
        let project = makeProject()
        project.addZoomRegion(at: 4.0)
        let id = project.zoomRegions[0].id
        project.setZoomRegionLevel(2.0, for: id)

        // At 2x, allowed focus range is x:[480,1440], y:[270,810] for 1920x1080.
        project.setZoomRegionFocus(x: -100, y: 5000, for: id)
        #expect(abs(project.zoomRegions[0].focusX - 480.0) < 0.0001)
        #expect(abs(project.zoomRegions[0].focusY - 810.0) < 0.0001)

        project.setZoomRegionFocus(x: 5000, y: -100, for: id)
        #expect(abs(project.zoomRegions[0].focusX - 1440.0) < 0.0001)
        #expect(abs(project.zoomRegions[0].focusY - 270.0) < 0.0001)
    }

    @Test func setZoomRegionTimesEnforcesBoundsAndMinimumDuration() {
        let project = makeProject(duration: 10)
        project.addZoomRegion(at: 5.0)
        let id = project.zoomRegions[0].id

        project.setZoomRegionTimes(start: -5.0, end: 0.05, for: id)
        #expect(abs(project.zoomRegions[0].startTime - 0.0) < 0.0001)
        #expect(abs(project.zoomRegions[0].endTime - 0.3) < 0.0001)

        project.setZoomRegionTimes(start: 9.95, end: 50.0, for: id)
        #expect(abs(project.zoomRegions[0].startTime - 9.7) < 0.0001)
        #expect(abs(project.zoomRegions[0].endTime - 10.0) < 0.0001)
    }

    @Test func duplicateZoomRegionClampsWhenOriginalEndsNearProjectEnd() {
        let project = makeProject(duration: 8)
        project.addZoomRegion(at: 7.5) // produces [6.5, 8.0]
        let original = project.zoomRegions[0]

        project.duplicateZoomRegion(original.id)

        #expect(project.zoomRegions.count == 2)
        let copy = project.zoomRegions[1]
        #expect(project.selectedZoomRegionID == copy.id)
        #expect(abs(copy.startTime - 6.5) < 0.0001)
        #expect(abs(copy.endTime - 8.0) < 0.0001)
        #expect(abs(copy.zoomLevel - original.zoomLevel) < 0.0001)
        #expect(abs(copy.focusX - original.focusX) < 0.0001)
        #expect(abs(copy.focusY - original.focusY) < 0.0001)
    }

    @Test func duplicateZoomRegionOffsetsAfterOriginalWhenSpaceAvailable() {
        let project = makeProject(duration: 12)
        project.addZoomRegion(at: 5.0) // [4.0, 6.0]
        let original = project.zoomRegions[0]

        project.duplicateZoomRegion(original.id)

        #expect(project.zoomRegions.count == 2)
        let copy = project.zoomRegions[1]
        #expect(abs(copy.startTime - 6.5) < 0.0001)
        #expect(abs(copy.endTime - 8.5) < 0.0001)
        #expect(abs(copy.zoomLevel - original.zoomLevel) < 0.0001)
        #expect(abs(copy.focusX - original.focusX) < 0.0001)
        #expect(abs(copy.focusY - original.focusY) < 0.0001)
    }

    @Test func addZoomRegionNearStartAndEndClampsToProjectBounds() {
        let project = makeProject(duration: 8)

        project.addZoomRegion(at: 0.1)
        #expect(project.zoomRegions.count == 1)
        #expect(abs(project.zoomRegions[0].startTime - 0.0) < 0.0001)
        #expect(abs(project.zoomRegions[0].endTime - 2.0) < 0.0001)

        project.addZoomRegion(at: 7.9)
        #expect(project.zoomRegions.count == 2)
        #expect(abs(project.zoomRegions[1].startTime - 6.9) < 0.0001)
        #expect(abs(project.zoomRegions[1].endTime - 8.0) < 0.0001)
    }

    @Test func toggleAndDeleteZoomRegionUpdateSelectionAndState() {
        let project = makeProject()
        project.addZoomRegion(at: 5.0)
        let id = project.zoomRegions[0].id

        project.toggleZoomRegion(id)
        #expect(project.zoomRegions[0].isEnabled == false)

        project.selectedZoomRegionID = id
        project.deleteZoomRegion(id)
        #expect(project.zoomRegions.isEmpty)
        #expect(project.selectedZoomRegionID == nil)
    }
}
