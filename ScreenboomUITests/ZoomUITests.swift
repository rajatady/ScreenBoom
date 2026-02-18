import XCTest

final class ZoomUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Auto Zoom Section
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testAutoZoomSectionShowsControls() throws {
        let app = launchApp(mode: "editor_cursor")
        waitForEditor(app)

        app.buttons["editor_tab_zoom"].tap()
        XCTAssertTrue(element("zoom_auto_section", in: app).waitForExistence(timeout: 3),
            "Auto zoom section card should be present")

        // Smart Zoom toggle
        XCTAssertTrue(app.staticTexts["Smart Zoom"].exists,
            "Smart Zoom toggle label should be present")

        // Auto-zoom is enabled by default in harness → expanded controls visible
        // Sensitivity tabs (AutoZoomSensitivity.allCases.map(\.displayName) → Subtle/Balanced/Dramatic)
        XCTAssertTrue(app.buttons["Subtle"].exists, "Subtle sensitivity option")
        XCTAssertTrue(app.buttons["Balanced"].exists, "Balanced sensitivity option")
        XCTAssertTrue(app.buttons["Dramatic"].exists, "Dramatic sensitivity option")

        // Default Zoom slider
        XCTAssertTrue(app.staticTexts["Default Zoom"].exists,
            "Default Zoom slider label should be present")

        // Regenerate button
        XCTAssertTrue(app.buttons["Regenerate"].exists,
            "Regenerate button should be present")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Manual Zoom Regions
    // ─────────────────────────────────────────────────────────────────

    // TODO: testManualZoomRegionList — when manual zoom region management ships
    // (currently zoom regions are created via timeline click, not zoom tab)

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Window-Following Crop (Tier 1)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testWindowFollowingCropToggle — when window-following crop ships
    // TODO: testWindowFollowingCropSensitivity — when window-following crop ships
}
