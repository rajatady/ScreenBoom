import XCTest

final class ExportUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Export Panel Content
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testExportPanelShowsAllControls() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        app.buttons["editor_export_button"].tap()

        // Wait for NSPanel popup
        XCTAssertTrue(
            app.buttons["Export MP4"].waitForExistence(timeout: 8),
            "Export MP4 button should appear in export popup")

        // Header
        XCTAssertTrue(app.staticTexts["Export"].exists, "Export header title")

        // Resolution label
        XCTAssertTrue(app.staticTexts["Resolution"].exists, "Resolution section label")

        // Resolution options (SBGlassTabs → buttons)
        XCTAssertTrue(app.buttons["1280 \u{00D7} 720"].exists, "720p option")
        XCTAssertTrue(app.buttons["1920 \u{00D7} 1080"].exists, "1080p option")
        XCTAssertTrue(app.buttons["2560 \u{00D7} 1440"].exists, "1440p option")
        XCTAssertTrue(app.buttons["3840 \u{00D7} 2160"].exists, "4K option")

        // Format chip
        XCTAssertTrue(app.staticTexts["H.264 MP4"].exists, "Format chip should show H.264 MP4")

        // Format label
        XCTAssertTrue(app.staticTexts["Format"].exists, "Format section label")

        // Close button — NSPanel elements are found by label, not by identifier
        XCTAssertTrue(app.buttons["Close export"].exists, "Close button")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Resolution Switching
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testResolutionSwitchingDoesNotCrash() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        app.buttons["editor_export_button"].tap()
        XCTAssertTrue(app.buttons["Export MP4"].waitForExistence(timeout: 8))

        // Cycle through all resolutions
        app.buttons["1280 \u{00D7} 720"].tap()
        app.buttons["2560 \u{00D7} 1440"].tap()
        app.buttons["3840 \u{00D7} 2160"].tap()
        app.buttons["1920 \u{00D7} 1080"].tap()

        // Should still be functional
        XCTAssertTrue(app.buttons["Export MP4"].exists,
            "Export button should remain after resolution switching")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Export Panel Dismiss
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testExportPanelCloseButton() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        app.buttons["editor_export_button"].tap()
        XCTAssertTrue(app.buttons["Export MP4"].waitForExistence(timeout: 8))

        // NSPanel elements are found by label, not by identifier
        let closeButton = app.buttons["Close export"]
        XCTAssertTrue(closeButton.exists, "Close button should be present")
        closeButton.tap()

        // Panel should dismiss
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["Export MP4"])
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testExportButtonTogglesPanel() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        // Open
        app.buttons["editor_export_button"].tap()
        XCTAssertTrue(app.buttons["Export MP4"].waitForExistence(timeout: 8))

        // Tap export button again → should dismiss (toggle behavior)
        app.buttons["editor_export_button"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["Export MP4"])
        waitForExpectations(timeout: 5)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Export Presets (Tier 2)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testExportPresetSelection — when export presets ship (e.g., "YouTube", "Twitter", "Custom")
    // TODO: testExportPresetChangesResolution — preset selection auto-sets resolution
    // TODO: testExportPresetChangesBitrate — preset selection auto-sets quality

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: GIF Export (Tier 3)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testGIFFormatOption — when GIF export ships
    // TODO: testGIFFrameRateControl — when GIF export ships
    // TODO: testGIFQualityControl — when GIF export ships

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Export Progress
    // ─────────────────────────────────────────────────────────────────

    // TODO: testExportProgressIndicator
    // Requires: triggering actual export (file picker interaction needed)
    // The export popup shows ProgressView when project.isExporting is true
    // Could be tested by injecting isExporting state in a harness mode

    // TODO: testExportToFileWritesValidMP4
    // Requires: sandbox file access + reading output file + AVAsset validation
    // This is an integration test, not a UI automation test.
}
