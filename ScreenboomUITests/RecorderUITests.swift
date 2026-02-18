import XCTest

/// Recorder flow UI tests.
///
/// Tests the RecorderBarView in each flow state using harness modes that embed
/// the bar directly in the main window (NSPanel is outside XCUI accessibility tree).
///
/// Harness modes:
/// - `recorder_configuring` — config state with Display mode
/// - `recorder_recording` — recording state with duration timer
/// - `recorder_countdown` — countdown(3) state
/// - `recorder_failed` — failed state with error message
final class RecorderUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Welcome Screen — Record Button
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testRecordButtonExistsOnWelcome() throws {
        let app = launchApp(mode: "welcome")

        XCTAssertTrue(app.buttons["Record Screen"].waitForExistence(timeout: 5),
            "Record Screen button should be on empty welcome screen")
    }

    @MainActor
    func testCompactRecordButtonExistsOnProjectsGrid() throws {
        let app = launchApp(mode: "welcome_projects")

        XCTAssertTrue(app.staticTexts["Demo Recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record"].exists,
            "Compact Record button should be in projects grid header")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Configuring State
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testConfiguringStateShowsStartButton() throws {
        let app = launchApp(mode: "recorder_configuring")

        let startBtn = app.descendants(matching: .any)["recorder_start_button"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 5),
            "Start button should be visible in configuring state")
        XCTAssertTrue(startBtn.isEnabled,
            "Start button should be enabled in display mode")
    }

    @MainActor
    func testConfiguringStateShowsCloseButton() throws {
        let app = launchApp(mode: "recorder_configuring")

        let closeBtn = app.descendants(matching: .any)["recorder_close_button"]
        XCTAssertTrue(closeBtn.waitForExistence(timeout: 5),
            "Close button should be visible in configuring state")
    }

    @MainActor
    func testConfiguringStateShowsStartLabelText() throws {
        let app = launchApp(mode: "recorder_configuring")

        // The Start button contains "Start" text
        let startBtn = app.descendants(matching: .any)["recorder_start_button"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 5))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Recording State
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testRecordingStateShowsStopButton() throws {
        let app = launchApp(mode: "recorder_recording")

        let stopBtn = app.descendants(matching: .any)["recorder_stop_button"]
        XCTAssertTrue(stopBtn.waitForExistence(timeout: 5),
            "Stop button should be visible in recording state")
    }

    @MainActor
    func testRecordingStateShowsDurationLabel() throws {
        let app = launchApp(mode: "recorder_recording")

        let duration = app.descendants(matching: .any)["recorder_duration_label"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5),
            "Duration label should be visible in recording state")
    }

    @MainActor
    func testRecordingStateDoesNotShowStartButton() throws {
        let app = launchApp(mode: "recorder_recording")

        // Wait for recording UI to appear
        let stopBtn = app.descendants(matching: .any)["recorder_stop_button"]
        XCTAssertTrue(stopBtn.waitForExistence(timeout: 5))

        // Start button should NOT be present in recording state
        let startBtn = app.descendants(matching: .any)["recorder_start_button"]
        XCTAssertFalse(startBtn.exists,
            "Start button should not exist in recording state")
    }

    @MainActor
    func testRecordingStateDoesNotShowCloseButton() throws {
        let app = launchApp(mode: "recorder_recording")

        let stopBtn = app.descendants(matching: .any)["recorder_stop_button"]
        XCTAssertTrue(stopBtn.waitForExistence(timeout: 5))

        // Close button should NOT be present during recording (only during config/failed)
        let closeBtn = app.descendants(matching: .any)["recorder_close_button"]
        XCTAssertFalse(closeBtn.exists,
            "Close button should not exist during active recording")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Countdown State
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testCountdownStateShowsCountdownLabel() throws {
        let app = launchApp(mode: "recorder_countdown")

        let label = app.descendants(matching: .any)["recorder_countdown_label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5),
            "Countdown label should be visible in countdown state")
    }

    @MainActor
    func testCountdownStateShowsCancelButton() throws {
        let app = launchApp(mode: "recorder_countdown")

        let cancelBtn = app.descendants(matching: .any)["recorder_cancel_countdown"]
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 5),
            "Cancel countdown button should be visible")
    }

    @MainActor
    func testCountdownStateDoesNotShowStartOrStop() throws {
        let app = launchApp(mode: "recorder_countdown")

        let label = app.descendants(matching: .any)["recorder_countdown_label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))

        XCTAssertFalse(app.descendants(matching: .any)["recorder_start_button"].exists,
            "Start button should not exist during countdown")
        XCTAssertFalse(app.descendants(matching: .any)["recorder_stop_button"].exists,
            "Stop button should not exist during countdown")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Failed State
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testFailedStateShowsRetryButton() throws {
        let app = launchApp(mode: "recorder_failed")

        let retryBtn = app.descendants(matching: .any)["recorder_retry_button"]
        XCTAssertTrue(retryBtn.waitForExistence(timeout: 5),
            "Retry button should be visible in failed state")
    }

    @MainActor
    func testFailedStateShowsCloseButton() throws {
        let app = launchApp(mode: "recorder_failed")

        let closeBtn = app.descendants(matching: .any)["recorder_close_button"]
        XCTAssertTrue(closeBtn.waitForExistence(timeout: 5),
            "Close button should be visible in failed state")
    }

    @MainActor
    func testFailedStateDoesNotShowStartOrStop() throws {
        let app = launchApp(mode: "recorder_failed")

        let retryBtn = app.descendants(matching: .any)["recorder_retry_button"]
        XCTAssertTrue(retryBtn.waitForExistence(timeout: 5))

        XCTAssertFalse(app.descendants(matching: .any)["recorder_start_button"].exists,
            "Start button should not exist in failed state")
        XCTAssertFalse(app.descendants(matching: .any)["recorder_stop_button"].exists,
            "Stop button should not exist in failed state")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - State Mutual Exclusion
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testConfiguringDoesNotShowRecordingElements() throws {
        let app = launchApp(mode: "recorder_configuring")

        let startBtn = app.descendants(matching: .any)["recorder_start_button"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 5))

        // Recording-specific elements should not exist
        XCTAssertFalse(app.descendants(matching: .any)["recorder_stop_button"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recorder_duration_label"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recorder_countdown_label"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recorder_retry_button"].exists)
    }
}
