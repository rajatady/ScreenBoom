import XCTest

final class EditorCoreUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Editor Layout (Real Video Pipeline)
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testEditorShowsCorePanels() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        // Toolbar
        XCTAssertTrue(app.buttons["editor_back_button"].exists,
            "Back button should be in toolbar")
        XCTAssertTrue(app.buttons["editor_export_button"].exists,
            "Export button should be in toolbar")

        // Tab bar — appearance always visible
        XCTAssertTrue(app.buttons["editor_tab_appearance"].exists,
            "Appearance tab should appear in editor")

        // Timeline — verify via leaf element IDs (no container IDs)
        XCTAssertTrue(app.buttons["timeline_play_button"].exists,
            "Play button should be in timeline")
        XCTAssertTrue(app.buttons["Split"].exists,
            "Split button should be in timeline")
        XCTAssertTrue(element("timeline_total_duration", in: app).exists,
            "Total duration label should be in timeline")
    }

    @MainActor
    func testEditorTabsWithoutCursorData() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        // Without cursor data: only appearance + coming-soon tabs
        XCTAssertTrue(app.buttons["editor_tab_appearance"].exists)

        XCTAssertFalse(app.buttons["editor_tab_cursor"].exists,
            "Cursor tab should be hidden without cursor data")
        XCTAssertFalse(app.buttons["editor_tab_zoom"].exists,
            "Zoom tab should be hidden without cursor data")

        // Coming-soon tabs always present
        XCTAssertTrue(app.buttons["editor_tab_audio"].exists,
            "Audio tab should always appear (disabled)")
        XCTAssertTrue(app.buttons["editor_tab_annotations"].exists,
            "Annotations tab should always appear (disabled)")
        XCTAssertTrue(app.buttons["editor_tab_subtitles"].exists,
            "Subtitles tab should always appear (disabled)")
    }

    @MainActor
    func testEditorTabsWithCursorData() throws {
        let app = launchApp(mode: "editor_cursor")
        waitForEditor(app)

        // All 6 tabs present
        XCTAssertTrue(app.buttons["editor_tab_appearance"].exists)
        XCTAssertTrue(app.buttons["editor_tab_cursor"].exists,
            "Cursor tab should appear with cursor data")
        XCTAssertTrue(app.buttons["editor_tab_zoom"].exists,
            "Zoom tab should appear with cursor data")
        XCTAssertTrue(app.buttons["editor_tab_audio"].exists)
        XCTAssertTrue(app.buttons["editor_tab_annotations"].exists)
        XCTAssertTrue(app.buttons["editor_tab_subtitles"].exists)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Navigation
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testBackButtonReturnsToWelcome() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        app.buttons["editor_back_button"].tap()

        // closeProject is async — wait for welcome to appear.
        // After returning, the store has the project we just created, so the
        // welcome screen shows the projects grid (not empty state).
        // The grid has compact "Import" and "Record" buttons.
        waitForWelcome(app)
        XCTAssertTrue(app.staticTexts["Screenboom"].exists,
            "Should see welcome screen after returning")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Tab Switching
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testTabSwitchingShowsCorrectContent() throws {
        let app = launchApp(mode: "editor_cursor")
        waitForEditor(app)

        // Default: Appearance tab — detect via section card ID
        XCTAssertTrue(element("appearance_background_section", in: app).waitForExistence(timeout: 3),
            "Appearance content should show by default")

        // Switch to Cursor — detect via section card ID
        app.buttons["editor_tab_cursor"].tap()
        XCTAssertTrue(element("cursor_section", in: app).waitForExistence(timeout: 3),
            "Cursor content should appear after switching")

        // Switch to Zoom — detect via section card ID
        app.buttons["editor_tab_zoom"].tap()
        XCTAssertTrue(element("zoom_auto_section", in: app).waitForExistence(timeout: 3),
            "Zoom content should appear after switching")

        // Switch back to Appearance
        app.buttons["editor_tab_appearance"].tap()
        XCTAssertTrue(element("appearance_background_section", in: app).waitForExistence(timeout: 3),
            "Appearance content should reappear")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Loading State
    // ─────────────────────────────────────────────────────────────────

    // NOTE: Loading placeholder is visible briefly during real pipeline mode.
    // Testing it deterministically requires intercepting the async load, which
    // isn't practical in XCUI. The placeholder accessibility ID is
    // "editor_loading_placeholder" if we ever need it.

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Undo/Redo
    // ─────────────────────────────────────────────────────────────────

    // TODO: testUndoRedoMenuCommands
    // Requires: perform an undoable action (split, change background), then Cmd+Z / Cmd+Shift+Z
    // XCUI can send keyboard shortcuts via typeKey("z", modifierFlags: .command)

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Webcam PiP
    // ─────────────────────────────────────────────────────────────────

    // TODO: testWebcamPiPToggle — when webcam PiP ships
    // TODO: testWebcamPiPPositionDrag — when webcam PiP ships
    // TODO: testWebcamPiPSizeControl — when webcam PiP ships
}
