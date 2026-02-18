import XCTest

/// Recorder flow UI tests.
///
/// IMPORTANT: Most recorder tests are blocked by ScreenCaptureKit's TCC permission dialog.
/// macOS requires user consent for screen recording — this dialog is a system-level modal
/// outside the app's accessibility tree, so XCUI cannot interact with it.
///
/// What IS testable: the recorder panel launch (before TCC), and the recorder bar UI
/// states IF we add a harness mode that bypasses the actual ScreenCaptureKit call.
final class RecorderUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Record Button Exists
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
    // MARK: - Future: Recorder Flow (requires TCC bypass harness)
    // ─────────────────────────────────────────────────────────────────

    // To test the recorder UI, we'd need a harness mode like "recorder_bar"
    // that creates a RecorderFlowController in a specific state (.configuring,
    // .recording, .countdown) without actually calling ScreenCaptureKit.

    // TODO: testRecorderBarConfiguring — recorder bar in config state
    //   - Source type picker (Display/Window/Region)
    //   - Start button
    //   - Close button

    // TODO: testRecorderBarCountdown — recorder bar in countdown state
    //   - 3-2-1 number visible (CountdownPanel is a separate NSPanel)

    // TODO: testRecorderBarRecording — recorder bar in recording state
    //   - Stop button
    //   - Duration timer
    //   - Pulsing red dot

    // TODO: testRecorderBarPause — when pause/resume ships

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Region Selection Overlay
    // ─────────────────────────────────────────────────────────────────

    // TODO: testRegionSelectionOverlayAppears — when region recording is selected
    // TODO: testRegionSelectionOverlayResize — drag edges to resize
    // Blocked: RegionSelectionOverlay is a full-screen NSWindow overlay,
    // XCUI may not have access to it as it's above the main app window.

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: System Audio + Mic (Tier 1)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testAudioSourcePicker — when system audio/mic recording ships
    // TODO: testMicToggle — microphone on/off toggle
    // TODO: testSystemAudioToggle — system audio capture toggle
}
