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
