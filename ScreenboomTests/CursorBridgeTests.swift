import Testing
import Foundation
@testable import Screenboom

struct CursorBridgeTests {

    // MARK: - Helpers

    /// Create a remap table with a source-time jump (simulating a disabled segment)
    private func makeRemapTableWithJump() -> TimeRemapTable {
        // Entries: [0-1s] maps to source [0-1s], then jumps to source [5-6s] at comp [1-2s]
        var entries: [TimeRemapEntry] = []
        // First segment: comp 0.0-1.0 maps to source 0.0-1.0
        for i in 0...60 {
            let t = Double(i) / 60.0
            entries.append(TimeRemapEntry(compositionTime: t, sourceTime: t))
        }
        // Jump: last entry of segment 1 at comp=1.0, source=1.0
        // First entry of segment 2 at comp=1.0+tiny, source=5.0 (gap of 4s source)
        entries.append(TimeRemapEntry(compositionTime: 1.001, sourceTime: 5.0))
        // Second segment: comp 1.001-2.0 maps to source 5.0-6.0
        for i in 1...60 {
            let t = 1.001 + Double(i) / 60.0
            let sourceT = 5.0 + Double(i) / 60.0
            entries.append(TimeRemapEntry(compositionTime: t, sourceTime: sourceT))
        }
        return TimeRemapTable(entries: entries)
    }

    /// Create a continuous remap table (no jumps)
    private func makeContinuousRemapTable() -> TimeRemapTable {
        var entries: [TimeRemapEntry] = []
        for i in 0...120 {
            let t = Double(i) / 60.0
            entries.append(TimeRemapEntry(compositionTime: t, sourceTime: t))
        }
        return TimeRemapTable(entries: entries)
    }

    /// Create test cursor points
    private func makePoints(count: Int, duration: Double) -> [SmoothedCursorPoint] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1) * duration
            return SmoothedCursorPoint(timestamp: t, x: Double(i * 10), y: Double(i * 5))
        }
    }

    // MARK: - Tests

    @Test func detectsSourceTimeJump() {
        let remapTable = makeRemapTableWithJump()
        // Create points that span the composition time range
        let points = makePoints(count: 120, duration: 2.0)

        let result = CursorOverlayEngine.injectCursorBridges(
            remappedPoints: points,
            remapTable: remapTable
        )

        // Bridge points should be injected, so result should have more points
        #expect(result.count > points.count)
    }

    @Test func noBridgeWhenContinuous() {
        let remapTable = makeContinuousRemapTable()
        let points = makePoints(count: 120, duration: 2.0)

        let result = CursorOverlayEngine.injectCursorBridges(
            remappedPoints: points,
            remapTable: remapTable
        )

        // No jumps → no bridges → same count
        #expect(result.count == points.count)
    }

    @Test func bridgeUsesSmootstepInterpolation() {
        let remapTable = makeRemapTableWithJump()
        let points = makePoints(count: 120, duration: 2.0)

        let result = CursorOverlayEngine.injectCursorBridges(
            remappedPoints: points,
            remapTable: remapTable
        )

        // Find bridge points (those NOT in original points by timestamp)
        let originalTimestamps = Set(points.map { $0.timestamp })
        let bridgePoints = result.filter { !originalTimestamps.contains($0.timestamp) }

        #expect(!bridgePoints.isEmpty, "Should have bridge points")

        // Bridge points should have timestamps clustered around the jump time (~1.0s comp time)
        let nearJump = bridgePoints.filter { $0.timestamp > 0.9 && $0.timestamp < 1.3 }
        #expect(!nearJump.isEmpty, "Bridge points should be near the jump at comp time ~1.0")
    }

    @Test func bridgeCountIs12PerJump() {
        let remapTable = makeRemapTableWithJump()
        let points = makePoints(count: 120, duration: 2.0)

        let result = CursorOverlayEngine.injectCursorBridges(
            remappedPoints: points,
            remapTable: remapTable
        )

        let bridgeCount = result.count - points.count
        #expect(bridgeCount == 12, "Expected 12 bridge points per jump, got \(bridgeCount)")
    }

    @Test func resultIsSortedByTimestamp() {
        let remapTable = makeRemapTableWithJump()
        let points = makePoints(count: 120, duration: 2.0)

        let result = CursorOverlayEngine.injectCursorBridges(
            remappedPoints: points,
            remapTable: remapTable
        )

        for i in 1..<result.count {
            #expect(result[i].timestamp >= result[i - 1].timestamp,
                    "Points should be sorted by timestamp, but \(result[i].timestamp) < \(result[i-1].timestamp)")
        }
    }
}
