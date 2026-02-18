import XCTest

final class CursorUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Cursor Section
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testCursorSectionShowsControls() throws {
        let app = launchApp(mode: "editor_cursor")
        waitForEditor(app)

        app.buttons["editor_tab_cursor"].tap()
        XCTAssertTrue(element("cursor_section", in: app).waitForExistence(timeout: 3),
            "Cursor section card should be present")

        // Show Cursor toggle
        XCTAssertTrue(app.staticTexts["Show Cursor"].exists,
            "Show Cursor toggle label should be present")

        // Cursor style tabs (CursorStyle.allCases.map(\.displayName) → Arrow/Pointer/Cross/Dot)
        XCTAssertTrue(app.buttons["Arrow"].exists, "Arrow cursor style option")
        XCTAssertTrue(app.buttons["Pointer"].exists, "Pointer cursor style option")
        XCTAssertTrue(app.buttons["Cross"].exists, "Cross cursor style option")
        XCTAssertTrue(app.buttons["Dot"].exists, "Dot cursor style option")

        // Size slider
        XCTAssertTrue(app.staticTexts["Size"].exists, "Size slider label should be present")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Click Effect Section
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testClickEffectSectionShowsControls() throws {
        let app = launchApp(mode: "editor_cursor")
        waitForEditor(app)

        app.buttons["editor_tab_cursor"].tap()
        XCTAssertTrue(element("cursor_click_effect_section", in: app).waitForExistence(timeout: 3),
            "Click effect section card should be present")

        // Ripple toggle
        XCTAssertTrue(app.staticTexts["Ripple on Click"].exists,
            "Ripple on Click toggle label should be present")

        // Ring Size slider (visible when both cursor and click effect are enabled)
        XCTAssertTrue(app.staticTexts["Ring Size"].exists,
            "Ring Size slider label should be present when click effect is enabled")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Click Spotlight (Tier 2)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testClickSpotlightToggle — when click spotlight ships
    // TODO: testClickSpotlightRadius — when click spotlight ships
    // TODO: testClickSpotlightOpacity — when click spotlight ships

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Cursor Trail (Tier 3)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testCursorTrailToggle — when cursor trail ships
    // TODO: testCursorTrailLength — when cursor trail ships
    // TODO: testCursorTrailColor — when cursor trail ships
}
