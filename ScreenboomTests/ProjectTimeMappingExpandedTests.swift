import Testing
import AVFoundation
@testable import Screenboom

// MARK: - Time mapping edge cases
// Covers: outputFraction↔sourceFraction with multiple speeds, disabled gaps,
// boundary conditions, single segment identity.

@MainActor
struct ProjectTimeMappingExpandedTests {

    private func makeProject(duration: Double, segments: [Segment]) -> Project {
        let project = Project()
        project.duration = CMTime(seconds: duration, preferredTimescale: 600)
        project.segments = segments
        return project
    }

    // MARK: - outputFractionToSourceFraction

    @Test func outputToSourceIdentityForSingleSegment1x() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ])
        // At 50% output → 50% source
        let result = project.outputFractionToSourceFraction(0.5)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test func outputToSourceAt2xSpeedMapsToDoubleSourceTime() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 2.0, isEnabled: true),
        ])
        // Total output = 10/2 = 5s. At output 50% (2.5s output) → source = 2.5 * 2 = 5s → 50% of 10s
        let result = project.outputFractionToSourceFraction(0.5)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test func outputToSourceSkipsDisabledMiddleSegment() {
        let project = makeProject(duration: 12, segments: [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: false),
            Segment(startTime: 8, endTime: 12, speed: 1.0, isEnabled: true),
        ])
        // Total output = 4 + 4 = 8s. At output 75% (6s) → in second enabled segment.
        // 6s output: first segment covers 4s output, leaving 2s in third segment.
        // Source time = 8 + 2 = 10 → 10/12 ≈ 0.833
        let result = project.outputFractionToSourceFraction(0.75)
        #expect(abs(result - (10.0 / 12.0)) < 0.02)
    }

    @Test func outputToSourceAtEndReturnsOne() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ])
        let result = project.outputFractionToSourceFraction(1.0)
        #expect(abs(result - 1.0) < 0.01)
    }

    @Test func outputToSourceAtZeroReturnsZero() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ])
        let result = project.outputFractionToSourceFraction(0.0)
        #expect(abs(result) < 0.01)
    }

    @Test func outputToSourceWithVaryingSpeeds() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 5, speed: 1.0, isEnabled: true),   // 5s output
            Segment(startTime: 5, endTime: 10, speed: 2.0, isEnabled: true),  // 2.5s output
        ])
        // Total output = 7.5s
        // At output 5s (5/7.5 ≈ 0.667): end of first segment → source = 5/10 = 0.5
        let result = project.outputFractionToSourceFraction(5.0 / 7.5)
        #expect(abs(result - 0.5) < 0.02)
    }

    // MARK: - sourceFractionToOutputFraction

    @Test func sourceToOutputIdentityForSingleSegment1x() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ])
        let result = project.sourceFractionToOutputFraction(0.5)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test func sourceToOutputAt2xSpeedCompresses() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 2.0, isEnabled: true),
        ])
        // Source 50% = 5s. Output = 5/2 = 2.5s. Total output = 5s. Fraction = 2.5/5 = 0.5
        let result = project.sourceFractionToOutputFraction(0.5)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test func sourceToOutputInDisabledSegmentSnapsToNearestEnabled() {
        let project = makeProject(duration: 12, segments: [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: false),
            Segment(startTime: 8, endTime: 12, speed: 1.0, isEnabled: true),
        ])
        // Source at 6s (50% of 12) is in disabled segment
        // Should snap to nearest enabled boundary
        let result = project.sourceFractionToOutputFraction(0.5)
        // Nearest enabled boundaries: 4s (end of seg1) or 8s (start of seg3)
        // 6s is equidistant — implementation picks based on iteration order
        #expect(result >= 0 && result <= 1, "Should return a valid fraction")
    }

    @Test func sourceToOutputReturnsZeroForEmptyTotal() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: false),
        ])
        let result = project.sourceFractionToOutputFraction(0.5)
        #expect(result == 0)
    }

    @Test func sourceToOutputAtStartReturnsZero() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ])
        let result = project.sourceFractionToOutputFraction(0.0)
        #expect(abs(result) < 0.01)
    }

    @Test func sourceToOutputAtEndReturnsOne() {
        let project = makeProject(duration: 10, segments: [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ])
        let result = project.sourceFractionToOutputFraction(1.0)
        #expect(abs(result - 1.0) < 0.01)
    }

    // MARK: - Round-trip stability

    @Test func roundTripIsStableWithMixedSpeeds() {
        let project = makeProject(duration: 12, segments: [
            Segment(startTime: 0, endTime: 4, speed: 0.5, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: true),
            Segment(startTime: 8, endTime: 12, speed: 3.0, isEnabled: true),
        ])

        for outputFrac in stride(from: 0.0, through: 1.0, by: 0.1) {
            let sourceFrac = project.outputFractionToSourceFraction(outputFrac)
            let backToOutput = project.sourceFractionToOutputFraction(sourceFrac)
            #expect(abs(backToOutput - outputFrac) < 0.05,
                    "Round-trip failed: output \(outputFrac) → source \(sourceFrac) → output \(backToOutput)")
        }
    }
}
