import XCTest

/// Shared base class for all Screenboom UI tests.
///
/// Provides launch helpers, common wait utilities, and constants.
/// Each feature-area test file subclasses this.
class ScreenboomUITestCase: XCTestCase {

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch Helpers

    /// Launch the app in a specific UI test harness mode.
    ///
    /// Modes (defined in ScreenboomApp.swift bootstrap):
    /// - `"welcome"` — empty welcome screen
    /// - `"welcome_projects"` — welcome screen with 3 synthetic project cards
    /// - `"editor"` — real video pipeline, 2 segments, no cursor data
    /// - `"editor_cursor"` — real video pipeline, 2 segments, cursor data (all 6 tabs)
    /// - `"editor_selected"` — synchronous fallback, segment pre-selected
    /// - `"editor_split"` — synchronous fallback, 3 segments, middle selected at split boundary
    /// - `"editor_cursor_zoom_selected"` — synchronous fallback, cursor data + zoom region selected
    @MainActor
    func launchApp(mode: String = "welcome") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SCREENBOOM_UI_TEST_MODE"] = mode
        app.launch()
        return app
    }

    // MARK: - Wait Helpers

    /// Wait for the editor to fully load.
    ///
    /// For real-pipeline modes (`editor`, `editor_cursor`), the Split button only appears
    /// after `isLoadingProject` becomes false and TimelineView renders.
    /// For fallback modes, this returns almost immediately.
    @MainActor
    func waitForEditor(_ app: XCUIApplication, timeout: TimeInterval = 15) {
        XCTAssertTrue(
            app.buttons["editor_back_button"].waitForExistence(timeout: timeout),
            "Editor back button should appear within \(timeout)s"
        )
        XCTAssertTrue(
            app.buttons["Split"].waitForExistence(timeout: timeout),
            "Split button should appear after editor finishes loading"
        )
    }

    /// Wait for the welcome screen to appear (after closing a project).
    @MainActor
    func waitForWelcome(_ app: XCUIApplication, timeout: TimeInterval = 15) {
        XCTAssertTrue(
            app.staticTexts["Screenboom"].waitForExistence(timeout: timeout),
            "Welcome screen title should appear within \(timeout)s"
        )
    }

    // MARK: - Element Helpers

    /// Find any element by accessibility identifier, regardless of type.
    @MainActor
    func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
}
