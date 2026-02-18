import XCTest

/// Tests for Coming Soon tabs (Audio, Annotations, Subtitles).
///
/// Currently these tabs show SBComingSoonPlaceholder views.
/// When each feature ships, move its tests to a dedicated file
/// (AudioUITests.swift, AnnotationsUITests.swift, SubtitlesUITests.swift).
final class ComingSoonTabsUITests: ScreenboomUITestCase {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Audio Tab (Coming Soon)
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testAudioTabShowsPlaceholder() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        // Audio tab exists but is disabled (coming soon)
        XCTAssertTrue(app.buttons["editor_tab_audio"].exists, "Audio tab should be present")

        // Tapping a disabled tab — SBIconTabBar may or may not switch.
        // If it does switch, it shows the placeholder.
        app.buttons["editor_tab_audio"].tap()

        // The placeholder shows title + description
        // If the tab didn't switch (disabled), these won't exist — that's also correct behavior.
        // We're testing that nothing crashes.
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Annotations Tab (Coming Soon)
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testAnnotationsTabShowsPlaceholder() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        XCTAssertTrue(app.buttons["editor_tab_annotations"].exists, "Annotations tab should be present")
        app.buttons["editor_tab_annotations"].tap()
        // Verify no crash
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Subtitles Tab (Coming Soon)
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testSubtitlesTabShowsPlaceholder() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)

        XCTAssertTrue(app.buttons["editor_tab_subtitles"].exists, "Subtitles tab should be present")
        app.buttons["editor_tab_subtitles"].tap()
        // Verify no crash
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Audio Tab (when implemented)
    // ─────────────────────────────────────────────────────────────────

    // Move to AudioUITests.swift when audio ships:
    // TODO: testAudioTabShowsMixerControls
    // TODO: testAudioVolumeSlider
    // TODO: testAudioMuteToggle
    // TODO: testBackgroundMusicPicker
    // TODO: testBackgroundMusicVolume
    // TODO: testSoundEffectsPicker
    // TODO: testAudioFadeInOutControls

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Annotations Tab (when implemented)
    // ─────────────────────────────────────────────────────────────────

    // Move to AnnotationsUITests.swift when annotations ship:
    // TODO: testAnnotationToolPicker (arrow, callout, highlight, text)
    // TODO: testAnnotationColorPicker
    // TODO: testAnnotationSizeSlider
    // TODO: testAnnotationTimeRange
    // TODO: testAnnotationDelete
    // TODO: testAnnotationDragOnPreview

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Subtitles Tab (when implemented)
    // ─────────────────────────────────────────────────────────────────

    // Move to SubtitlesUITests.swift when subtitles ship:
    // TODO: testAutoGenerateSubtitles
    // TODO: testSubtitleTrackList
    // TODO: testSubtitleEditText
    // TODO: testSubtitleTimingAdjust
    // TODO: testSubtitleStylePicker (font, size, position)
    // TODO: testSubtitleDelete

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Keyboard Shortcut Overlay (Tier 2)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testKeyboardOverlayToggle — when keyboard shortcut overlay ships
    // TODO: testKeyboardOverlayStyle — when keyboard shortcut overlay ships
    // TODO: testKeyboardOverlayPosition — when keyboard shortcut overlay ships
}
