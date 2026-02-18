import Testing
@testable import Screenboom

struct CompositionEngineRemapTests {

    private func assertMonotonic(_ entries: [TimeRemapEntry]) {
        guard entries.count > 1 else { return }
        for i in 1..<entries.count {
            #expect(entries[i].compositionTime >= entries[i - 1].compositionTime)
            #expect(entries[i].sourceTime >= entries[i - 1].sourceTime)
        }
    }

    @Test func buildTimeRemapTableEmptySegmentsReturnsEmptyTable() {
        let table = CompositionEngine.buildTimeRemapTable(segments: [])
        #expect(table.entries.isEmpty)
    }

    @Test func singleSegmentSpeedTwoMapsTenSecondsSourceToFiveSecondsComposition() {
        let segments = [
            Segment(startTime: 0, endTime: 10, speed: 2.0, isEnabled: true),
        ]

        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        #expect(!table.entries.isEmpty)
        assertMonotonic(table.entries)

        let first = table.entries.first!
        let last = table.entries.last!
        #expect(abs(first.compositionTime - 0.0) < 0.0001)
        #expect(abs(first.sourceTime - 0.0) < 0.0001)

        #expect(abs(last.sourceTime - 10.0) < 0.05)
        #expect(abs(last.compositionTime - 5.0) < 0.1)
    }

    @Test func contiguousEqualSpeedSegmentsApproximateIdentityMapping() {
        let segments = [
            Segment(startTime: 0, endTime: 5, speed: 1.0, isEnabled: true),
            Segment(startTime: 5, endTime: 10, speed: 1.0, isEnabled: true),
        ]

        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        #expect(!table.entries.isEmpty)
        assertMonotonic(table.entries)

        let remap = TimeRemapTable(entries: table.entries)
        for t in stride(from: 0.0, through: 10.0, by: 1.0) {
            let source = remap.sourceTime(forCompositionTime: t)
            #expect(abs(source - t) < 0.15, "expected identity around \(t), got \(source)")
        }
    }

    @Test func discontinuousSegmentsRetainSourceGapAndCompositionContinuity() {
        let segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 8, endTime: 12, speed: 2.0, isEnabled: true),
        ]

        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        #expect(!table.entries.isEmpty)
        assertMonotonic(table.entries)

        // output duration should be 4 + (4 / 2) = 6s (within ramp approximation tolerance)
        let totalComp = table.entries.last!.compositionTime
        #expect(abs(totalComp - 6.0) < 0.2)

        // There should be at least one substantial source jump due to removed [4,8) range.
        var largestSourceJump = 0.0
        var smallestCompDelta = Double.greatestFiniteMagnitude
        for i in 1..<table.entries.count {
            let sourceJump = table.entries[i].sourceTime - table.entries[i - 1].sourceTime
            let compDelta = table.entries[i].compositionTime - table.entries[i - 1].compositionTime
            largestSourceJump = max(largestSourceJump, sourceJump)
            if compDelta > 0 { smallestCompDelta = min(smallestCompDelta, compDelta) }
        }

        #expect(largestSourceJump > 0.15)
        #expect(smallestCompDelta >= 0)
    }

    @Test func remapInterpolationIsStableAtBoundsAndMiddle() {
        let segments = [
            Segment(startTime: 0, endTime: 3, speed: 1.0, isEnabled: true),
            Segment(startTime: 3, endTime: 6, speed: 3.0, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        let remap = TimeRemapTable(entries: table.entries)

        // clamp to first/last source times
        #expect(remap.sourceTime(forCompositionTime: -10) <= 0.01)
        #expect(remap.sourceTime(forCompositionTime: 999) >= 5.9)

        // composition midpoint should map inside valid source range
        let midComp = (table.entries.first!.compositionTime + table.entries.last!.compositionTime) / 2
        let midSource = remap.sourceTime(forCompositionTime: midComp)
        #expect(midSource >= 0 && midSource <= 6)
    }
}
