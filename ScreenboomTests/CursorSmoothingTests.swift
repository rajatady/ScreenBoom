import Testing
import Foundation
@testable import Screenboom

// MARK: - Cursor Smoothing Tests
// Covers: smoothPositions edge cases (single point, zero duration),
// Catmull-Rom boundary control points, prepare with minimal data.

struct CursorSmoothingTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - smoothPositions (via prepare)
    // smoothPositions is private — tested through prepare()
    // ─────────────────────────────────────────────────────────────────

    @Test func prepareSinglePointReturnsOneSmoothedPoint() {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 100, y: 980, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 60
        )

        // Single point → smoothPositions returns it directly (< 2 points)
        #expect(state.smoothedPoints.count == 1)
        #expect(abs(state.smoothedPoints[0].x - 100) < 0.0001)
    }

    @Test func prepareTwoPointsProducesInterpolatedSamples() {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 100, y: 980, type: .move, button: nil),
                CursorEvent(timestamp: 1.0, x: 200, y: 880, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 10
        )

        // 1 second at 10fps → ~10-11 smoothed points
        #expect(state.smoothedPoints.count >= 10 && state.smoothedPoints.count <= 11,
                "Expected ~10 points at 10fps over 1s, got \(state.smoothedPoints.count)")

        // First and last should approximately match input
        #expect(abs(state.smoothedPoints.first!.x - 100) < 1)
        #expect(abs(state.smoothedPoints.last!.x - 200) < 1)
    }

    @Test func prepareZeroDurationReturnsEmpty() {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 100, y: 980, type: .move, button: nil),
                CursorEvent(timestamp: 0.0, x: 200, y: 880, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 60
        )

        // Two points at timestamp 0.0 → totalDuration = 0 → returns empty
        #expect(state.smoothedPoints.isEmpty)
    }

    @Test func smoothingPreservesMonotonicTimestamps() {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 100, y: 980, type: .move, button: nil),
                CursorEvent(timestamp: 0.3, x: 400, y: 700, type: .move, button: nil),
                CursorEvent(timestamp: 0.8, x: 800, y: 500, type: .move, button: nil),
                CursorEvent(timestamp: 2.0, x: 1500, y: 200, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 30
        )

        for i in 1..<state.smoothedPoints.count {
            #expect(state.smoothedPoints[i].timestamp > state.smoothedPoints[i - 1].timestamp,
                    "Smoothed points should have monotonically increasing timestamps")
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Catmull-Rom Boundary Behavior
    // Tested via prepare: at boundaries, control points clamp to first/last
    // ─────────────────────────────────────────────────────────────────

    @Test func catmullRomDoesNotOvershotWithStraightLine() {
        // Three collinear points — Catmull-Rom should not overshoot
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 100, y: 980, type: .move, button: nil),
                CursorEvent(timestamp: 1.0, x: 500, y: 580, type: .move, button: nil),
                CursorEvent(timestamp: 2.0, x: 900, y: 180, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 10
        )

        // All x values should be in [100, 900] (no overshoot for linear input)
        for point in state.smoothedPoints {
            #expect(point.x >= 95 && point.x <= 905,
                    "Catmull-Rom should not overshoot on linear path: x=\(point.x)")
        }
    }

    @Test func catmullRomHandlesReversalWithoutCrash() {
        // Points that reverse direction — should produce valid output
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 100, y: 980, type: .move, button: nil),
                CursorEvent(timestamp: 0.5, x: 900, y: 180, type: .move, button: nil),
                CursorEvent(timestamp: 1.0, x: 100, y: 980, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 20
        )

        // Should produce valid output without NaN or infinity
        for point in state.smoothedPoints {
            #expect(point.x.isFinite, "Smoothed x should be finite")
            #expect(point.y.isFinite, "Smoothed y should be finite")
        }
    }

    @Test func catmullRomHandlesIdenticalAdjacentPoints() {
        // Two identical points followed by a move — guard segDuration > 0.0001
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 1080,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 500, y: 500, type: .move, button: nil),
                CursorEvent(timestamp: 0.001, x: 500, y: 500, type: .move, button: nil),
                CursorEvent(timestamp: 1.0, x: 1000, y: 800, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: CursorSettings(),
            outputFrameRate: 10
        )

        #expect(state.smoothedPoints.count >= 10)
        for point in state.smoothedPoints {
            #expect(point.x.isFinite)
            #expect(point.y.isFinite)
        }
    }
}
