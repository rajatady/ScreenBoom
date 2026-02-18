import XCTest

final class PerformanceUITests: ScreenboomUITestCase {

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Performance Benchmarks
    // ─────────────────────────────────────────────────────────────────

    // TODO: testEditorLoadPerformance
    // measure { launchApp(mode: "editor") } — tracks video loading + UI render time

    // TODO: testTabSwitchPerformance
    // Launch in editor_cursor, then measure tab switching latency

    // TODO: testExportStartPerformance
    // Measure time from tapping Export MP4 to first progress update
}
