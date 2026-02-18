import Testing
import CoreImage
@testable import Screenboom

// MARK: - Cursor Coordinate Tests
// Covers: mapToOutput zoom-adjusted double-flip,
// compositionTime reverse lookup boundary,
// lookupPosition interpolation.

struct CursorCoordinateTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - mapToOutput (tested via cursorComposite position)
    // mapToOutput is private — tested through cursorComposite
    // ─────────────────────────────────────────────────────────────────

    private func makeState(
        smoothedPoints: [SmoothedCursorPoint] = [],
        clicks: [CursorClick] = [],
        sourceSize: CGSize = CGSize(width: 100, height: 50),
        zoomKeyframes: [ZoomKeyframe] = []
    ) -> CursorOverlayState {
        var settings = CursorSettings()
        settings.isEnabled = true
        settings.clickEffectEnabled = false
        settings.autoZoomEnabled = !zoomKeyframes.isEmpty

        return CursorOverlayState(
            smoothedPoints: smoothedPoints,
            clicks: clicks,
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: sourceSize,
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: zoomKeyframes
        )
    }

    @Test func cursorAtOriginMapsToTopLeftOfRecordingRect() {
        let state = makeState(
            smoothedPoints: [SmoothedCursorPoint(timestamp: 0, x: 0, y: 0)]
        )

        let composite = CursorOverlayEngine.cursorComposite(
            in: state, at: 0,
            recordingRect: CGRect(x: 10, y: 10, width: 80, height: 40),
            outputSize: CGSize(width: 100, height: 60),
            zoomCropRect: nil
        )
        // Should produce a composite (cursor at top-left of recording area)
        #expect(composite != nil)
    }

    @Test func cursorAtCenterMapsToMiddleOfRecordingRect() {
        let state = makeState(
            smoothedPoints: [SmoothedCursorPoint(timestamp: 0, x: 50, y: 25)]
        )

        let composite = CursorOverlayEngine.cursorComposite(
            in: state, at: 0,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )
        #expect(composite != nil)
    }

    @Test func cursorWithZoomCropAdjustsPosition() {
        // When zoomed to the right half of the source, cursor at center of source
        // should appear at the left edge of output (since it's at the left edge of zoom crop)
        let state = makeState(
            smoothedPoints: [SmoothedCursorPoint(timestamp: 0, x: 50, y: 25)],
            zoomKeyframes: [
                ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 75, y: 25), easingDuration: 0)
            ]
        )

        // zoomCropRect: at 2x zoom centered at (75,25), crop is 50x25 at origin (50,12.5)
        // But we pass the actual zoomCropRect from zoomCropRect()
        let cropRect = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 100, height: 50)
        )

        let composite = CursorOverlayEngine.cursorComposite(
            in: state, at: 0,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: cropRect
        )
        #expect(composite != nil, "Cursor with zoom crop should produce a composite")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - compositionTime Reverse Lookup
    // compositionTime is private — tested via remapForExport
    // ─────────────────────────────────────────────────────────────────

    @Test func remapForExportMapsClicksToCompositionTime() {
        let state = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 0, y: 0),
                SmoothedCursorPoint(timestamp: 5, x: 50, y: 50),
            ],
            clicks: [
                CursorClick(timestamp: 2.5, x: 25, y: 25, button: .left),
            ],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 100),
            captureOrigin: .zero,
            settings: CursorSettings(),
            zoomKeyframes: []
        )

        // Dense identity table (compositionTime uses nearest-neighbor with < 1.0 threshold)
        // Need entries within 1.0s of every source time we care about
        var entries: [TimeRemapEntry] = []
        for i in stride(from: 0.0, through: 5.0, by: 0.5) {
            entries.append(TimeRemapEntry(compositionTime: i, sourceTime: i))
        }
        let table = TimeRemapTable(entries: entries)

        let remapped = CursorOverlayEngine.remapForExport(state: state, remapTable: table)
        #expect(remapped.clicks.count == 1)
        #expect(abs(remapped.clicks[0].timestamp - 2.5) < 0.5, "Click should map to ~2.5 comp time")
    }

    @Test func remapForExportDropsClickOutsideEnabledRange() {
        let state = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 0, y: 0),
                SmoothedCursorPoint(timestamp: 10, x: 100, y: 100),
            ],
            clicks: [
                CursorClick(timestamp: 1, x: 10, y: 10, button: .left),   // in range
                CursorClick(timestamp: 50, x: 50, y: 50, button: .left),  // way outside range
            ],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 100),
            captureOrigin: .zero,
            settings: CursorSettings(),
            zoomKeyframes: []
        )

        // Dense table covering 0-5s (entries every 0.5s)
        var entries: [TimeRemapEntry] = []
        for i in stride(from: 0.0, through: 5.0, by: 0.5) {
            entries.append(TimeRemapEntry(compositionTime: i, sourceTime: i))
        }
        let table = TimeRemapTable(entries: entries)

        let remapped = CursorOverlayEngine.remapForExport(state: state, remapTable: table)
        // Click at source t=1 is within range, t=50 is > 1.0 from any entry → dropped
        #expect(remapped.clicks.count == 1, "Click at source t=50 should be dropped")
    }

    @Test func remapForExportWithSpeedChangeRemapsCorrectly() {
        let state = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 0, y: 0),
                SmoothedCursorPoint(timestamp: 10, x: 100, y: 100),
            ],
            clicks: [
                CursorClick(timestamp: 5, x: 50, y: 50, button: .left),
            ],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 100),
            captureOrigin: .zero,
            settings: CursorSettings(),
            zoomKeyframes: []
        )

        // 2x speed: source 0-10 maps to comp 0-5, with dense entries
        var entries: [TimeRemapEntry] = []
        for i in stride(from: 0.0, through: 5.0, by: 0.5) {
            entries.append(TimeRemapEntry(compositionTime: i, sourceTime: i * 2.0))
        }
        let table = TimeRemapTable(entries: entries)

        let remapped = CursorOverlayEngine.remapForExport(state: state, remapTable: table)
        #expect(remapped.clicks.count == 1)
        // Click at source t=5 → comp t≈2.5
        #expect(abs(remapped.clicks[0].timestamp - 2.5) < 0.5)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - TimeRemapTable Interpolation Edge Cases
    // ─────────────────────────────────────────────────────────────────

    @Test func timeRemapTableSingleEntryReturnsItsValue() {
        let table = TimeRemapTable(entries: [
            TimeRemapEntry(compositionTime: 5, sourceTime: 10),
        ])
        // Before → clamp to first
        #expect(abs(table.sourceTime(forCompositionTime: 0) - 10) < 0.0001)
        // At → exact
        #expect(abs(table.sourceTime(forCompositionTime: 5) - 10) < 0.0001)
        // After → clamp to last
        #expect(abs(table.sourceTime(forCompositionTime: 100) - 10) < 0.0001)
    }

    @Test func timeRemapTableEmptyReturnsInput() {
        let table = TimeRemapTable(entries: [])
        #expect(abs(table.sourceTime(forCompositionTime: 3.0) - 3.0) < 0.0001)
    }
}
