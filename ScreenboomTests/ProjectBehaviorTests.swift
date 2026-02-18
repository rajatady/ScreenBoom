import Testing
import AVFoundation
@testable import Screenboom

@MainActor
struct ProjectBehaviorTests {

    private func makeProject(duration: Double = 12) -> Project {
        let project = Project()
        project.duration = CMTime(seconds: duration, preferredTimescale: 600)
        project.segments = [
            Segment(startTime: 0, endTime: duration, speed: 1.0, isEnabled: true),
        ]
        return project
    }

    private func configureMixedSegments(_ project: Project) {
        project.duration = CMTime(seconds: 12, preferredTimescale: 600)
        project.segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: false),
            Segment(startTime: 8, endTime: 12, speed: 2.0, isEnabled: true),
        ]
    }

    @Test func addSplitRejectsEdgesAndNearDuplicates() {
        let project = makeProject(duration: 10)

        project.addSplit(at: 0.02)   // too close to start
        project.addSplit(at: 9.98)   // too close to end
        #expect(project.splitPoints.isEmpty)
        #expect(project.segments.count == 1)

        project.addSplit(at: 5.0)
        #expect(project.splitPoints.count == 1)
        #expect(project.segments.count == 2)

        project.addSplit(at: 5.03)   // within duplicate tolerance
        #expect(project.splitPoints.count == 1)
        #expect(project.segments.count == 2)
    }

    @Test func removeSplitOutOfBoundsIsNoOp() {
        let project = makeProject(duration: 8)
        project.addSplit(at: 2)
        project.addSplit(at: 6)
        #expect(project.splitPoints.count == 2)

        project.removeSplit(at: -1)
        project.removeSplit(at: 99)
        #expect(project.splitPoints.count == 2)
        #expect(project.segments.count == 3)
    }

    @Test func setSpeedClampsSegmentRange() {
        let project = makeProject()
        let id = project.segments[0].id

        project.setSpeed(100, for: id)
        #expect(project.segments[0].speed == 32.0)

        project.setSpeed(0.01, for: id)
        #expect(project.segments[0].speed == 0.25)
    }

    @Test func outputFractionToSourceFractionUsesEnabledSegmentsAndSpeed() {
        let project = makeProject()
        configureMixedSegments(project)

        // Total output = 4s + (4s / 2x) = 6s
        #expect(abs(project.totalOutputDuration - 6.0) < 0.0001)

        let sourceFracA = project.outputFractionToSourceFraction(0.5)
        // output t=3.0s -> source t=3.0s -> 3/12 = 0.25
        #expect(abs(sourceFracA - 0.25) < 0.0001)

        let sourceFracC = project.outputFractionToSourceFraction(0.75)
        // output t=4.5s -> 0.5s into seg C at 2x => +1.0 source -> 9.0/12 = 0.75
        #expect(abs(sourceFracC - 0.75) < 0.0001)
    }

    @Test func sourceFractionToOutputFractionSnapsInsideDisabledSegment() {
        let project = makeProject()
        configureMixedSegments(project)

        // source t in disabled [4,8] snaps to the nearest enabled boundary.
        // In this fixture both boundaries collapse to the SAME output time:
        // end(segA)=4s output and start(segC)=4s output -> fraction 4/6.
        let disabledMid = project.sourceFractionToOutputFraction(6.0 / 12.0)
        #expect(abs(disabledMid - (4.0 / 6.0)) < 0.0001)

        // Near the upper edge of the disabled segment still snaps to the same collapsed boundary.
        let nearEnd = project.sourceFractionToOutputFraction(7.2 / 12.0)
        #expect(abs(nearEnd - (4.0 / 6.0)) < 0.0001)
    }

    @Test func sourceOutputRoundTripIsStableInsideEnabledRanges() {
        let project = makeProject()
        configureMixedSegments(project)

        let sourceFractions: [Double] = [1.0 / 12.0, 3.0 / 12.0, 9.0 / 12.0, 11.0 / 12.0]

        for source in sourceFractions {
            let output = project.sourceFractionToOutputFraction(source)
            let remappedSource = project.outputFractionToSourceFraction(output)
            #expect(abs(source - remappedSource) < 0.001, "round trip drift for \(source): got \(remappedSource)")
        }
    }

    @Test func toggleSegmentUpdatesEnabledStateAndDuration() {
        let project = makeProject()
        configureMixedSegments(project)

        let segA = project.segments[0].id
        #expect(project.segments[0].isEnabled)
        #expect(abs(project.totalOutputDuration - 6.0) < 0.0001)

        project.toggleSegment(segA)
        #expect(!project.segments[0].isEnabled)
        // Only segC remains enabled: 4s at 2x = 2s
        #expect(abs(project.totalOutputDuration - 2.0) < 0.0001)
    }

    @Test func splitInheritsDisabledStateAndSpeedFromParentSegment() {
        let project = makeProject(duration: 10)
        project.segments = [
            Segment(startTime: 0, endTime: 10, speed: 3.0, isEnabled: false),
        ]

        project.addSplit(at: 5)

        #expect(project.segments.count == 2)
        #expect(project.segments[0].isEnabled == false)
        #expect(project.segments[1].isEnabled == false)
        #expect(abs(project.segments[0].speed - 3.0) < 0.0001)
        #expect(abs(project.segments[1].speed - 3.0) < 0.0001)
    }

    @Test func sourceToOutputReturnsZeroWhenAllSegmentsDisabled() {
        let project = makeProject(duration: 10)
        project.segments = [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: false),
        ]

        let outputFraction = project.sourceFractionToOutputFraction(0.75)
        #expect(abs(outputFraction) < 0.0001)
    }
}
