import XCTest

final class ScreenboomUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(mode: String = "welcome") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SCREENBOOM_UI_TEST_MODE"] = mode
        app.launch()
        return app
    }

    @MainActor
    func testWelcomeEmptyStateElementsExist() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["Import Video"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record Screen"].exists)
    }

    @MainActor
    func testEditorHarnessShowsCorePanels() throws {
        let app = launchApp(mode: "editor")

        XCTAssertTrue(app.buttons["editor_back_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor_export_button"].exists)
        XCTAssertTrue(app.buttons["Split"].exists)

        // Verify controls panel tab bar renders — find appearance tab by its identifier
        XCTAssertTrue(app.buttons["editor_tab_appearance"].waitForExistence(timeout: 5),
            "Appearance tab should appear in editor mode")
    }

    @MainActor
    func testEditorCursorHarnessRendersAllTabPanels() throws {
        let app = launchApp(mode: "editor_cursor")

        // Wait for editor to fully load
        XCTAssertTrue(app.buttons["editor_back_button"].waitForExistence(timeout: 8))

        // Verify all 6 tab buttons are present (cursor + zoom are conditional on cursor data)
        XCTAssertTrue(app.buttons["editor_tab_appearance"].waitForExistence(timeout: 5),
            "Appearance tab should always appear")
        XCTAssertTrue(app.buttons["editor_tab_cursor"].exists,
            "Cursor tab should appear in editor_cursor mode")
        XCTAssertTrue(app.buttons["editor_tab_zoom"].exists,
            "Zoom tab should appear in editor_cursor mode")
        XCTAssertTrue(app.buttons["editor_tab_audio"].exists)
        XCTAssertTrue(app.buttons["editor_tab_annotations"].exists)
        XCTAssertTrue(app.buttons["editor_tab_subtitles"].exists)

        // Switch to cursor tab
        app.buttons["editor_tab_cursor"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cursor_tab_root"].waitForExistence(timeout: 3))

        // Switch to zoom tab
        app.buttons["editor_tab_zoom"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["zoom_tab_root"].waitForExistence(timeout: 3))

        // Switch back to appearance tab
        app.buttons["editor_tab_appearance"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["appearance_tab_root"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testExportPanelOpenAndClose() throws {
        let app = launchApp(mode: "editor")

        let exportButton = app.buttons["editor_export_button"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let confirmButton = app.buttons["Export MP4"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
