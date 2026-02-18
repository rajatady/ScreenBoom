import XCTest

final class WelcomeUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Empty State
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testEmptyStateElements() throws {
        let app = launchApp(mode: "welcome")

        // Core action buttons
        XCTAssertTrue(app.buttons["Import Video"].waitForExistence(timeout: 5),
            "Import Video button should appear on empty welcome screen")
        XCTAssertTrue(app.buttons["Record Screen"].exists,
            "Record Screen button should appear on empty welcome screen")

        // Branding
        XCTAssertTrue(app.staticTexts["Screenboom"].exists,
            "App title should be visible")
        XCTAssertTrue(app.staticTexts["Make your screen recordings look professional"].exists,
            "Subtitle should be visible")

        // Drop hint (leaf ID — no longer overridden by parent container)
        XCTAssertTrue(element("welcome_drop_hint", in: app).exists,
            "Drag-and-drop hint should be visible")
    }

    @MainActor
    func testEmptyStateDoesNotShowProjectGrid() throws {
        let app = launchApp(mode: "welcome")

        XCTAssertTrue(app.buttons["Import Video"].waitForExistence(timeout: 5))

        // Should NOT have project grid elements
        XCTAssertFalse(app.staticTexts["Recent Projects"].exists,
            "Recent Projects header should not appear when store is empty")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Projects Grid
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testProjectsGridShowsCards() throws {
        let app = launchApp(mode: "welcome_projects")

        // Project names from harness
        XCTAssertTrue(app.staticTexts["Demo Recording"].waitForExistence(timeout: 5),
            "Project card 'Demo Recording' should appear")
        XCTAssertTrue(app.staticTexts["Product Tour"].exists,
            "Project card 'Product Tour' should appear")
        XCTAssertTrue(app.staticTexts["Bug Report"].exists,
            "Project card 'Bug Report' should appear")

        // Header
        XCTAssertTrue(app.staticTexts["Recent Projects"].exists,
            "Recent Projects header should appear")

        // Metadata chips on cards
        XCTAssertTrue(app.staticTexts["1920\u{00D7}1080"].exists,
            "Resolution chip should appear on Demo Recording card")
        XCTAssertTrue(app.staticTexts["3840\u{00D7}2160"].exists,
            "Resolution chip should appear on Bug Report card")
    }

    @MainActor
    func testProjectsGridHasCompactButtons() throws {
        let app = launchApp(mode: "welcome_projects")

        XCTAssertTrue(app.staticTexts["Demo Recording"].waitForExistence(timeout: 5))

        // Compact header buttons (not the full empty-state ones)
        XCTAssertTrue(app.buttons["Import"].exists,
            "Compact Import button should appear in header")
        XCTAssertTrue(app.buttons["Record"].exists,
            "Compact Record button should appear in header")

        // Should NOT have the big empty-state buttons
        XCTAssertFalse(app.buttons["Import Video"].exists,
            "Full 'Import Video' button should not appear when projects exist")
        XCTAssertFalse(app.buttons["Record Screen"].exists,
            "Full 'Record Screen' button should not appear when projects exist")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Project Card Actions
    // ─────────────────────────────────────────────────────────────────

    // TODO: testProjectCardOpenNavigatesToEditor
    // Requires: tapping a project card should load it and transition to editor.
    // Blocked: project cards need real video files on disk to load successfully.
    // Will work once we persist the cached test video into project directories.

    // TODO: testProjectCardRename
    // Requires: hover to reveal pencil icon → tap → TextField → type → submit

    // TODO: testProjectCardDelete
    // Requires: hover to reveal trash icon → tap → confirm alert → card disappears

    // TODO: testProjectCardDurationChip
    // Verify duration formatting (e.g., "0:45", "2:00", "0:08")

    // TODO: testDragAndDropImport
    // XCUI can't simulate drag from Finder. Manual test only.
}
