import Testing
import CoreImage
@testable import Screenboom

// MARK: - Cursor Zoom Interpolation Tests
// Covers: interpolateZoom instant cut, clampFocusPoint boundary at extreme zoom,
// zoomCropRect calculation accuracy.

struct CursorZoomInterpolationTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - interpolateZoom (tested via zoomCropRect)
    // interpolateZoom is private — tested through zoomCropRect
    // ─────────────────────────────────────────────────────────────────

    private func makeState(
        zoomKeyframes: [ZoomKeyframe],
        sourceSize: CGSize = CGSize(width: 1000, height: 500)
    ) -> CursorOverlayState {
        var settings = CursorSettings()
        settings.autoZoomEnabled = true

        return CursorOverlayState(
            smoothedPoints: [],
            clicks: [],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: sourceSize,
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: zoomKeyframes
        )
    }

    @Test func zoomCropRectAtUnityReturnsNil() {
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusPoint: CGPoint(x: 500, y: 250), easingDuration: 0)
        ])

        let crop = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )
        #expect(crop == nil, "Zoom at 1.0 should return nil crop rect")
    }

    @Test func zoomCropRectAt2xReturnsCorrctSize() {
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 500, y: 250), easingDuration: 0)
        ])

        let crop = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )

        #expect(crop != nil)
        guard let crop else { return }
        #expect(abs(crop.width - 500) < 1, "2x zoom crop width should be 500, got \(crop.width)")
        #expect(abs(crop.height - 250) < 1, "2x zoom crop height should be 250, got \(crop.height)")
    }

    @Test func zoomCropRectCentersOnFocusPoint() {
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 500, y: 250), easingDuration: 0)
        ])

        let crop = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )
        guard let crop else { return }

        // Focus (500,250) in top-left coords → CIImage bottom-left: ciFocusY = 500 - 250 = 250
        // Crop centered at (500, 250): x=250, y=125 (CIImage coords)
        #expect(abs(crop.midX - 500) < 1)
        #expect(abs(crop.midY - 250) < 1)
    }

    @Test func zoomCropRectClampsAtTopLeftEdge() {
        // Focus near top-left corner — crop should be clamped to not go outside bounds
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 10, y: 10), easingDuration: 0)
        ])

        let crop = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )
        guard let crop else { return }

        #expect(crop.minX >= 0, "Crop should not go left of source")
        #expect(crop.maxX <= 1000, "Crop should not go right of source")
        #expect(crop.minY >= 0, "Crop should not go below source")
        #expect(crop.maxY <= 500, "Crop should not go above source")
    }

    @Test func zoomCropRectClampsAtBottomRightEdge() {
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 990, y: 490), easingDuration: 0)
        ])

        let crop = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )
        guard let crop else { return }

        #expect(crop.minX >= 0)
        #expect(crop.maxX <= 1000)
        #expect(crop.minY >= 0)
        #expect(crop.maxY <= 500)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Instant Cut (easingDuration = 0)
    // ─────────────────────────────────────────────────────────────────

    @Test func interpolateZoomInstantCutSnapsToTargetZoom() {
        // easingDuration = 0 → guard range > 0.001 returns next.zoomLevel immediately
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusPoint: CGPoint(x: 500, y: 250), easingDuration: 0),
            ZoomKeyframe(timestamp: 1, zoomLevel: 3.0, focusPoint: CGPoint(x: 200, y: 100), easingDuration: 0),
        ])

        // At t=0.5 (between keyframes), easingDuration=0 → snap to next
        let crop = CursorOverlayEngine.zoomCropRect(
            in: state, at: 0.5,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )
        guard let crop else {
            Issue.record("Should produce crop at 3x zoom")
            return
        }

        // At 3x zoom, crop size = 1000/3 ≈ 333 × 500/3 ≈ 167
        #expect(abs(crop.width - 1000.0 / 3.0) < 2, "Instant cut should snap to 3x: width=\(crop.width)")
    }

    @Test func interpolateZoomSmoothstepBetweenKeyframes() {
        // Two keyframes with proper easing → at midpoint should be interpolated
        let state = makeState(zoomKeyframes: [
            ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusPoint: CGPoint(x: 500, y: 250), easingDuration: 0),
            ZoomKeyframe(timestamp: 2, zoomLevel: 2.0, focusPoint: CGPoint(x: 500, y: 250), easingDuration: 2.0),
        ])

        let cropAt1s = CursorOverlayEngine.zoomCropRect(
            in: state, at: 1.0,
            sourceExtent: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )

        // At t=1.0, u = 1.0/2.0 = 0.5, smoothstep(0.5) = 0.5
        // zoom = 1.0 + (2.0 - 1.0) * 0.5 = 1.5
        // cropW = 1000 / 1.5 ≈ 667
        if let crop = cropAt1s {
            #expect(abs(crop.width - 1000.0 / 1.5) < 10,
                    "Smoothstep midpoint should give ~1.5x zoom: width=\(crop.width)")
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - clampFocusPoint (tested via generateZoomRegions)
    // ─────────────────────────────────────────────────────────────────

    @Test func clampFocusPointKeepsFocusInsideViewport() {
        // At extreme zoom (4x), focus point at corner should be clamped inward
        let sourceSize = CGSize(width: 1000, height: 500)
        let clicks = [
            CursorClick(timestamp: 1.0, x: 10, y: 10, button: .left),
            CursorClick(timestamp: 1.1, x: 15, y: 15, button: .left),
            CursorClick(timestamp: 1.2, x: 12, y: 8, button: .left),
        ]

        let regions = CursorOverlayEngine.generateZoomRegions(
            clicks: clicks,
            keyInteractions: [],
            sensitivity: .balanced,
            zoomLevel: 4.0,
            sourceSize: sourceSize
        )

        guard !regions.isEmpty else {
            Issue.record("Should generate at least one region")
            return
        }

        for region in regions {
            // At 4x: halfW = (1000/4)/2 = 125, halfH = (500/4)/2 = 62.5
            // focus should be in [125, 875] x [62.5, 437.5]
            #expect(region.focusX >= 125, "Focus X should be clamped: \(region.focusX)")
            #expect(region.focusX <= 875, "Focus X should be clamped: \(region.focusX)")
            #expect(region.focusY >= 62.5, "Focus Y should be clamped: \(region.focusY)")
            #expect(region.focusY <= 437.5, "Focus Y should be clamped: \(region.focusY)")
        }
    }

    @Test func clampFocusPointAtCenterRemainsUnchanged() {
        let sourceSize = CGSize(width: 1000, height: 500)
        let clicks = [
            CursorClick(timestamp: 1.0, x: 500, y: 250, button: .left),
            CursorClick(timestamp: 1.1, x: 500, y: 250, button: .left),
        ]

        let regions = CursorOverlayEngine.generateZoomRegions(
            clicks: clicks,
            keyInteractions: [],
            sensitivity: .balanced,
            zoomLevel: 2.0,
            sourceSize: sourceSize
        )

        guard !regions.isEmpty else { return }

        // Center point should remain at center (no clamping needed)
        #expect(abs(regions[0].focusX - 500) < 5, "Center focus should remain at 500")
        #expect(abs(regions[0].focusY - 250) < 5, "Center focus should remain at 250")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Zoom Keyframes from Regions
    // ─────────────────────────────────────────────────────────────────

    @Test func zoomKeyframesEmptyRegionsReturnsEmpty() {
        let keyframes = CursorOverlayEngine.zoomKeyframes(
            from: [],
            sensitivity: .balanced,
            sourceSize: CGSize(width: 1000, height: 500)
        )
        #expect(keyframes.isEmpty)
    }

    @Test func zoomKeyframesAllDisabledReturnsEmpty() {
        let regions = [
            ZoomRegion(startTime: 1, endTime: 3, zoomLevel: 2.0, focusX: 500, focusY: 250, isEnabled: false),
        ]
        let keyframes = CursorOverlayEngine.zoomKeyframes(
            from: regions,
            sensitivity: .balanced,
            sourceSize: CGSize(width: 1000, height: 500)
        )
        #expect(keyframes.isEmpty)
    }

    @Test func zoomKeyframesProducesCorrectStructure() {
        let regions = [
            ZoomRegion(startTime: 2, endTime: 5, zoomLevel: 1.8, focusX: 500, focusY: 250),
        ]
        let keyframes = CursorOverlayEngine.zoomKeyframes(
            from: regions,
            sensitivity: .balanced,
            sourceSize: CGSize(width: 1000, height: 500)
        )

        // Expected: [initial@0, hold@1.5, zoom-in@2, hold-peak@4.2, zoom-out@5]
        #expect(keyframes.count == 5)
        #expect(abs(keyframes[0].zoomLevel - 1.0) < 0.01, "First keyframe should be at 1.0x")
        #expect(keyframes[2].zoomLevel > 1.5, "Peak keyframe should be at zoom level")
        #expect(abs(keyframes.last!.zoomLevel - 1.0) < 0.01, "Last keyframe should return to 1.0x")

        // All timestamps should be monotonically increasing
        for i in 1..<keyframes.count {
            #expect(keyframes[i].timestamp >= keyframes[i - 1].timestamp)
        }
    }
}
