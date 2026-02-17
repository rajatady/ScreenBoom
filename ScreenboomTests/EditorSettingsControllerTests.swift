import Testing
import Foundation
import SwiftUI
@testable import Screenboom

@MainActor
struct EditorSettingsControllerTests {

    // MARK: - Helpers

    private func makeProject() -> Project {
        let project = Project()
        // Set up minimal state for testing
        project.segments = [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true)
        ]
        return project
    }

    private func makeController(project: Project? = nil) -> EditorSettingsController {
        EditorSettingsController(project: project ?? makeProject())
    }

    // MARK: - Tab Availability

    @Test func cursorTabHiddenWithoutCursorData() {
        let controller = makeController()
        // No cursor data loaded → hasCursorData is false
        #expect(!controller.hasCursorData)
        let tabs = controller.availableTabs
        #expect(!tabs.contains(.cursor))
        #expect(!tabs.contains(.zoom))
        #expect(tabs.contains(.appearance))
    }

    @Test func disabledTabsReturnComingSoonState() {
        #expect(EditorTab.audio.isComingSoon)
        #expect(EditorTab.annotations.isComingSoon)
        #expect(EditorTab.subtitles.isComingSoon)
        #expect(!EditorTab.appearance.isComingSoon)
        #expect(!EditorTab.cursor.isComingSoon)
        #expect(!EditorTab.zoom.isComingSoon)
    }

    // MARK: - Background Presets

    @Test func applyPresetUpdatesGradientColors() {
        let project = makeProject()
        let controller = makeController(project: project)

        controller.applyPreset("Ocean")

        let ns1 = NSColor(project.gradientColor1).usingColorSpace(.sRGB)!
        let ns2 = NSColor(project.gradientColor2).usingColorSpace(.sRGB)!

        // Ocean preset: (0.05, 0.1, 0.3) → (0.1, 0.2, 0.5)
        #expect(abs(ns1.redComponent - 0.05) < 0.02)
        #expect(abs(ns1.greenComponent - 0.1) < 0.02)
        #expect(abs(ns1.blueComponent - 0.3) < 0.02)
        #expect(abs(ns2.redComponent - 0.1) < 0.02)
        #expect(abs(ns2.greenComponent - 0.2) < 0.02)
        #expect(abs(ns2.blueComponent - 0.5) < 0.02)
    }

    @Test func currentPresetDetectsMatch() {
        let project = makeProject()
        let controller = makeController(project: project)

        controller.applyPreset("Dark")
        #expect(controller.currentPreset == "Dark")

        controller.applyPreset("Light")
        #expect(controller.currentPreset == "Light")

        controller.applyPreset("Ocean")
        #expect(controller.currentPreset == "Ocean")
    }

    // MARK: - Segment Operations

    @Test func toggleSegmentFlipsEnabled() {
        let project = makeProject()
        let controller = makeController(project: project)
        let segmentID = project.segments[0].id

        #expect(project.segments[0].isEnabled)
        controller.toggleSegment(segmentID)
        #expect(!project.segments[0].isEnabled)
    }

    @Test func segmentSpeedClampsToValidRange() {
        let project = makeProject()
        let controller = makeController(project: project)
        let segmentID = project.segments[0].id

        controller.setSegmentSpeed(100, for: segmentID)
        #expect(project.segments[0].speed == 32.0)

        controller.setSegmentSpeed(0.01, for: segmentID)
        #expect(project.segments[0].speed == 0.25)
    }

    // MARK: - Zoom Region Operations

    @Test func deleteZoomRegionClearsSelection() {
        let project = makeProject()
        let region = ZoomRegion(startTime: 1.0, endTime: 3.0, zoomLevel: 2.0, focusX: 500, focusY: 300)
        project.zoomRegions = [region]
        project.selectedZoomRegionID = region.id

        let controller = makeController(project: project)
        #expect(controller.selectedZoomRegion != nil)

        project.deleteZoomRegion(region.id)
        #expect(controller.selectedZoomRegion == nil)
        #expect(project.selectedZoomRegionID == nil)
    }

    // MARK: - Inspector

    @Test func hasInspectorContentWhenZoomRegionSelected() {
        let project = makeProject()
        let region = ZoomRegion(startTime: 0, endTime: 2, zoomLevel: 1.5, focusX: 100, focusY: 100)
        project.zoomRegions = [region]
        project.selectedZoomRegionID = region.id

        let controller = makeController(project: project)
        #expect(controller.hasInspectorContent)
    }

    @Test func hasInspectorContentWhenSegmentSelected() {
        let project = makeProject()
        project.selectedSegmentId = project.segments[0].id

        let controller = makeController(project: project)
        #expect(controller.hasInspectorContent)
    }

    @Test func noInspectorContentByDefault() {
        let controller = makeController()
        #expect(!controller.hasInspectorContent)
    }

    @Test func dismissInspectorClearsBothSelections() {
        let project = makeProject()
        let region = ZoomRegion(startTime: 0, endTime: 2, zoomLevel: 1.5, focusX: 100, focusY: 100)
        project.zoomRegions = [region]
        project.selectedZoomRegionID = region.id
        project.selectedSegmentId = project.segments[0].id

        let controller = makeController(project: project)
        controller.dismissInspector()

        #expect(project.selectedZoomRegionID == nil)
        #expect(project.selectedSegmentId == nil)
    }

    // MARK: - Cursor Settings

    @Test func setCursorStyleUpdatesProject() {
        let project = makeProject()
        let controller = makeController(project: project)

        controller.setCursorStyle(.crosshair)
        #expect(project.cursorSettings.style == .crosshair)
    }

    @Test func setClickEffectEnabledUpdatesProject() {
        let project = makeProject()
        let controller = makeController(project: project)

        controller.setClickEffectEnabled(false)
        #expect(!project.cursorSettings.clickEffectEnabled)
    }

    // MARK: - Output Resolution

    @Test func setOutputResolutionUpdatesProject() {
        let project = makeProject()
        let controller = makeController(project: project)

        controller.setOutputResolution(width: 1920, height: 1080)
        #expect(project.outputWidth == 1920)
        #expect(project.outputHeight == 1080)
    }
}
