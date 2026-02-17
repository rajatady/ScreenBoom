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

    // MARK: - Background Type

    @Test func setBackgroundTypeSolidUpdatesProject() {
        let project = makeProject()
        let controller = makeController(project: project)

        let solidColor = CodableColor(red: 0.5, green: 0.3, blue: 0.1)
        controller.setBackgroundType(.solid(solidColor))

        if case .solid(let c) = project.backgroundStyle {
            #expect(abs(c.red - 0.5) < 0.01)
        } else {
            Issue.record("Expected .solid background type")
        }
    }

    @Test func setFrameStyleBorderUpdatesProject() {
        let project = makeProject()
        let controller = makeController(project: project)

        let borderColor = CodableColor(red: 1, green: 0, blue: 0)
        controller.setFrameStyle(.border(width: 3, color: borderColor))

        if case .border(let w, let c) = project.frameStyle {
            #expect(w == 3)
            #expect(abs(c.red - 1.0) < 0.01)
        } else {
            Issue.record("Expected .border frame style")
        }
    }

    @Test func legacyGradientColorsWorkWithBackgroundStyle() {
        let project = makeProject()
        // Default is .gradient — verify backward compat accessors work
        let c1 = project.gradientColor1
        let ns1 = NSColor(c1).usingColorSpace(.sRGB)!
        // Default dark gradient: (0.08, 0.08, 0.12)
        #expect(abs(ns1.redComponent - 0.08) < 0.02)

        // Setting via accessor should update backgroundStyle
        project.gradientColor1 = Color(red: 0.5, green: 0.5, blue: 0.5)
        if case .gradient(let gc1, _) = project.backgroundStyle {
            #expect(abs(gc1.red - 0.5) < 0.02)
        } else {
            Issue.record("Setting gradientColor1 should maintain .gradient type")
        }
    }

    @Test func backgroundTypeSelectionMatchesCurrentStyle() {
        let project = makeProject()
        let controller = makeController(project: project)

        // Default is gradient
        #expect(controller.backgroundTypeSelection == .gradient)

        project.backgroundStyle = .solid(CodableColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(controller.backgroundTypeSelection == .solid)

        project.backgroundStyle = .wallpaper("Sunset")
        #expect(controller.backgroundTypeSelection == .wallpaper)
    }
}
