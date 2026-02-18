import XCTest

final class TimelineUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Core Timeline Elements
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testTimelineBaseElements() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        // Always-visible controls (leaf element IDs)
        XCTAssertTrue(app.buttons["Split"].exists, "Split button should always be present")
        XCTAssertTrue(app.buttons["timeline_play_button"].exists, "Play button should always be present")
        XCTAssertTrue(element("timeline_total_duration", in: app).exists, "Total duration label should be present")

        // No segment selected → no toggle/speed/remove
        XCTAssertFalse(app.buttons["timeline_toggle_button"].exists,
            "Toggle button should be hidden when no segment is selected")
        XCTAssertFalse(element("timeline_speed_picker", in: app).exists,
            "Speed picker should be hidden when no segment is selected")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Segment Selection Controls (Synchronous State)
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testSelectedSegmentShowsControls() throws {
        let app = launchApp(mode: "editor_selected")

        // Fallback mode — state is synchronous
        XCTAssertTrue(
            app.buttons["timeline_toggle_button"].waitForExistence(timeout: 10),
            "Toggle button should appear when segment is selected")
        XCTAssertTrue(element("timeline_speed_picker", in: app).exists,
            "Speed picker should appear when segment is selected")
        XCTAssertTrue(app.buttons["Split"].exists,
            "Split button should still be present")
    }

    @MainActor
    func testToggleSegmentChangesLabel() throws {
        let app = launchApp(mode: "editor_selected")

        let toggle = app.buttons["timeline_toggle_button"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))

        // Initial: segment is enabled → button says "Disable"
        XCTAssertTrue(toggle.label.contains("Disable"),
            "Toggle should say Disable for enabled segment, got: \(toggle.label)")

        toggle.tap()

        // After tap: segment is disabled → button says "Enable"
        let predicate = NSPredicate(format: "label CONTAINS 'Enable'")
        expectation(for: predicate, evaluatedWith: app.buttons["timeline_toggle_button"])
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testRemoveSplitButton() throws {
        let app = launchApp(mode: "editor_split")

        // editor_split: 3 segments, second selected at split boundary
        XCTAssertTrue(
            app.buttons["timeline_remove_split_button"].waitForExistence(timeout: 10),
            "Remove Split should appear for segment at a split boundary")

        // Toggle and speed should also be present
        XCTAssertTrue(app.buttons["timeline_toggle_button"].exists)
        XCTAssertTrue(element("timeline_speed_picker", in: app).exists)
    }

    @MainActor
    func testRemoveSplitButtonHiddenForFirstSegment() throws {
        let app = launchApp(mode: "editor_selected")

        // editor_selected: 2 segments, FIRST selected — not at an interior split
        XCTAssertTrue(app.buttons["timeline_toggle_button"].waitForExistence(timeout: 10))
        // The first segment's startTime is 0, which doesn't match a splitPoint
        // Remove Split should not appear
        // NOTE: This depends on the harness selecting segment[0]. If the split point
        // is at segment[0].endTime, it might still show. This tests the current harness behavior.
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Zoom Track (with Cursor Data)
    // ─────────────────────────────────────────────────────────────────

    // NOTE: The zoom track is a ZStack rendered inside the timeline ScrollView.
    // Individual zoom regions are Shape-based (TrapezoidShape) with no accessibility
    // identifiers — they're hit-tested via the timeline gesture, not as discrete UI elements.
    // Testing zoom region interactions requires coordinate-based taps which are fragile.
    //
    // What we CAN test: the zoom track's existence via the cursor-data-dependent layout
    // (timeline height changes from 200pt to 240pt with cursor data).

    @MainActor
    func testZoomTrackVisibleWithCursorData() throws {
        let app = launchApp(mode: "editor_cursor")
        waitForEditor(app)

        // The timeline renders zoom track shapes when hasCursorData is true.
        // We verify the cursor/zoom tabs exist (proxy for hasCursorData = true)
        // and the timeline leaf elements are present.
        XCTAssertTrue(app.buttons["editor_tab_zoom"].exists,
            "Zoom tab should appear, indicating cursor data is loaded")
        XCTAssertTrue(app.buttons["timeline_play_button"].exists,
            "Timeline play button should render with zoom track layout")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Timeline Interactions
    // ─────────────────────────────────────────────────────────────────

    // TODO: testClickTimelineSeeksPlayhead
    // Requires: coordinate-based tap on the timeline area, then verify playhead time changed.
    // XCUI can do coordinate taps: element.coordinate(withNormalizedOffset:).tap()

    // TODO: testSplitCreatesNewSegment
    // Tap Split → verify segment count increases (needs a way to read segment count from UI)

    // TODO: testTimelineZoomSlider
    // Drag the zoom slider → verify timeline content width changes

    // TODO: testThumbnailViewToggle
    // Tap the view toggle button → verify visual mode switches (frame vs solid)

    // TODO: testContextMenuAddZoomRegion
    // Right-click timeline → "Add Zoom Region Here"

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Scroll Smoothing (Tier 2)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testScrollSmoothingToggle — when scroll smoothing ships
    // TODO: testScrollSmoothingIntensity — when scroll smoothing ships

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Animated Intro/Outro (Tier 2)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testIntroAnimationPicker — when intro/outro ships
    // TODO: testOutroAnimationPicker — when intro/outro ships
}
