import XCTest

final class InspectorUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Segment Inspector
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testSegmentInspectorShowsAllControls() throws {
        let app = launchApp(mode: "editor_selected")

        // Segment inspector should appear (pre-selected in fallback mode).
        // Detect via unique content: "Duration" label only appears in segment inspector.
        XCTAssertTrue(
            app.staticTexts["Duration"].waitForExistence(timeout: 10),
            "Segment inspector should appear when a segment is selected")

        // Speed section
        XCTAssertTrue(app.staticTexts["Speed"].exists, "Speed label")

        // Speed quick tabs (SBGlassTabs → buttons)
        XCTAssertTrue(app.buttons["0.5x"].exists, "0.5x speed option")
        XCTAssertTrue(app.buttons["1x"].exists, "1x speed option")
        XCTAssertTrue(app.buttons["2x"].exists, "2x speed option")
        XCTAssertTrue(app.buttons["4x"].exists, "4x speed option")

        // Custom speed slider
        XCTAssertTrue(app.staticTexts["Custom"].exists, "Custom speed slider label")

        // Enabled toggle
        XCTAssertTrue(app.staticTexts["Enabled"].exists, "Enabled toggle label")

        // Dismiss button (leaf ID, no longer overridden by parent container)
        XCTAssertTrue(app.buttons["inspector_dismiss_button"].exists, "Dismiss button")
    }

    @MainActor
    func testSegmentInspectorDismiss() throws {
        let app = launchApp(mode: "editor_selected")

        // Wait for inspector content
        XCTAssertTrue(app.staticTexts["Duration"].waitForExistence(timeout: 10))

        app.buttons["inspector_dismiss_button"].tap()

        // Inspector should disappear — "Duration" label goes away
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Duration"])
        waitForExpectations(timeout: 5)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Zoom Region Inspector
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testZoomRegionInspectorShowsAllControls() throws {
        let app = launchApp(mode: "editor_cursor_zoom_selected")

        // Zoom region inspector (pre-selected in fallback mode).
        // Detect via unique content: "Zoom Level" label only appears in zoom region inspector.
        XCTAssertTrue(
            app.staticTexts["Zoom Level"].waitForExistence(timeout: 10),
            "Zoom region inspector should appear when a zoom region is selected")

        // Time range sliders
        XCTAssertTrue(app.staticTexts["Start"].exists, "Start time slider label")
        XCTAssertTrue(app.staticTexts["End"].exists, "End time slider label")

        // Focus point section
        XCTAssertTrue(app.staticTexts["Focus Point"].exists, "Focus Point label")

        // Enabled toggle
        XCTAssertTrue(app.staticTexts["Enabled"].exists, "Enabled toggle label")

        // Delete button
        XCTAssertTrue(app.buttons["Delete Region"].exists, "Delete Region button")

        // Dismiss button
        XCTAssertTrue(app.buttons["inspector_dismiss_button"].exists, "Dismiss button")
    }

    @MainActor
    func testZoomRegionInspectorDismiss() throws {
        let app = launchApp(mode: "editor_cursor_zoom_selected")

        XCTAssertTrue(app.staticTexts["Zoom Level"].waitForExistence(timeout: 10))

        app.buttons["inspector_dismiss_button"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Zoom Level"])
        waitForExpectations(timeout: 5)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Inspector Mutual Exclusion
    // ─────────────────────────────────────────────────────────────────

    // NOTE: Segment inspector and zoom region inspector are mutually exclusive.
    // When a segment is selected, zoom region is deselected, and vice versa.
    // Testing this in XCUI requires selecting a segment (timeline click) then
    // a zoom region (zoom track click) — coordinate-based, fragile.

    // TODO: testSegmentAndZoomInspectorMutuallyExclusive
    // Click timeline segment → "Duration" label appears (segment inspector)
    // Click zoom region → "Zoom Level" label appears (zoom inspector), "Duration" gone

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Annotations Inspector (Tier 3)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testAnnotationInspectorShowsControls — when annotations ship
    // Would appear when tapping an annotation overlay on the preview
}
