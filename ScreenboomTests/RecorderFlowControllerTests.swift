import Testing
import Foundation
@preconcurrency import ScreenCaptureKit
@testable import Screenboom

@MainActor
struct RecorderFlowControllerTests {
    final class MockRecorderService: RecorderServiceProtocol {
        var state: ScreenRecorder.State = .idle
        var availableDisplays: [SCDisplay] = []
        var availableWindows: [SCWindow] = []
        var captureMode: CaptureMode = .display
        var selectedDisplay: SCDisplay?
        var selectedWindow: SCWindow?
        var selectedRegion: CGRect?
        var frameRate: Int = 60
        var enableCursorTracking: Bool = true

        var permissionResult: ScreenRecorder.State = .ready
        var startResult: ScreenRecorder.State = .recording
        var stopResult: ScreenRecorder.State = .completed(
            RecordingSession(
                videoURL: URL(fileURLWithPath: "/tmp/mock.mp4"),
                cursorMetadataURL: nil,
                duration: 1.0,
                sourceSize: CGSize(width: 1920, height: 1080),
                frameRate: 60,
                displayName: "Mock Session",
                startDate: Date(timeIntervalSince1970: 0)
            )
        )

        var requestCalls = 0
        var refreshCalls = 0
        var startCalls = 0
        var stopCalls = 0
        var resetCalls = 0

        func requestPermission() async {
            requestCalls += 1
            state = permissionResult
        }

        func refreshWindows() async {
            refreshCalls += 1
        }

        func startRecording() async {
            startCalls += 1
            state = startResult
        }

        func stopRecording() async {
            stopCalls += 1
            state = stopResult
        }

        func reset() {
            resetCalls += 1
            state = .ready
        }
    }

    final class MockRegionSelector: RegionSelectorManaging {
        var startCalls = 0
        var forceCloseCalls = 0
        private var onSelected: ((CGRect) -> Void)?
        private var onCancelled: (() -> Void)?

        func startSelection(onSelected: @escaping (CGRect) -> Void, onCancelled: (() -> Void)?) {
            startCalls += 1
            self.onSelected = onSelected
            self.onCancelled = onCancelled
        }

        func forceClose() {
            forceCloseCalls += 1
        }

        func emitSelection(_ rect: CGRect) {
            onSelected?(rect)
        }

        func emitCancel() {
            onCancelled?()
        }
    }

    final class MockCountdownPanel: CountdownPanelManaging {
        var showCalls = 0
        var dismissCalls = 0
        var updates: [Int] = []

        func show(on screen: NSScreen) {
            _ = screen
            showCalls += 1
        }

        func updateCount(_ count: Int) {
            updates.append(count)
        }

        func dismiss() {
            dismissCalls += 1
        }
    }

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(for: .milliseconds(Int(milliseconds)))
    }

    private func makeSession(name: String = "Region 1280x720") -> RecordingSession {
        RecordingSession(
            videoURL: URL(fileURLWithPath: "/tmp/session.mp4"),
            cursorMetadataURL: URL(fileURLWithPath: "/tmp/session.cursor.json"),
            duration: 4.2,
            sourceSize: CGSize(width: 1280, height: 720),
            frameRate: 60,
            displayName: name,
            startDate: Date(timeIntervalSince1970: 123)
        )
    }

    @Test func requestPermissionTransitionsToConfiguringOnReady() async {
        let recorder = MockRecorderService()
        recorder.permissionResult = .ready
        let region = MockRegionSelector()

        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: region,
            countdownPanelFactory: { MockCountdownPanel() }
        )

        await flow.requestPermission()

        #expect(flow.flowState == .configuring)
        #expect(recorder.requestCalls == 1)
    }

    @Test func requestPermissionTransitionsToFailedOnError() async {
        let recorder = MockRecorderService()
        recorder.permissionResult = .failed("Permission denied")

        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: MockRegionSelector(),
            countdownPanelFactory: { MockCountdownPanel() }
        )

        await flow.requestPermission()

        switch flow.flowState {
        case .failed(let message):
            #expect(message == "Permission denied")
        default:
            Issue.record("Expected failed state, got \(flow.flowState)")
        }
    }

    @Test func switchingToRegionInConfiguringStartsSelection() {
        let recorder = MockRecorderService()
        let region = MockRegionSelector()
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: region,
            countdownPanelFactory: { MockCountdownPanel() }
        )

        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region

        #expect(flow.flowState == .selectingRegion)
        #expect(region.startCalls == 1)
    }

    @Test func switchingAwayFromRegionWhileSelectingForceClosesOverlay() {
        let recorder = MockRecorderService()
        let region = MockRegionSelector()
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: region,
            countdownPanelFactory: { MockCountdownPanel() }
        )

        flow.captureMode = .region
        flow._setFlowStateForTesting(.selectingRegion)
        flow.captureMode = .display

        #expect(flow.flowState == .configuring)
        #expect(region.forceCloseCalls == 1)
    }

    @Test func regionSelectionCallbackSetsRegionAndEnablesStart() {
        let recorder = MockRecorderService()
        let region = MockRegionSelector()
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: region,
            countdownPanelFactory: { MockCountdownPanel() }
        )

        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region
        region.emitSelection(CGRect(x: 12, y: 20, width: 640, height: 360))

        #expect(flow.flowState == .configuring)
        #expect(flow.selectedRegion == CGRect(x: 12, y: 20, width: 640, height: 360))
        #expect(flow.canStart)
    }

    @Test func cancelCountdownReturnsToConfiguring() {
        let recorder = MockRecorderService()
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: MockRegionSelector(),
            countdownPanelFactory: { MockCountdownPanel() }
        )

        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display
        flow.initiateRecording()
        #expect(flow.flowState == .countdown(3))

        flow.cancelCountdown()
        #expect(flow.flowState == .configuring)
    }

    @Test func initiateRecordingCompletesCountdownAndStartsRecorder() async {
        let recorder = MockRecorderService()
        recorder.startResult = .recording
        let countdownPanel = MockCountdownPanel()
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: MockRegionSelector(),
            countdownPanelFactory: { countdownPanel }
        )

        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display
        flow.countdownStepScheduler = { _, action in action() }

        flow.initiateRecording()
        await wait(milliseconds: 20)

        #expect(flow.flowState == .recording)
        #expect(recorder.startCalls == 1)
        #expect(countdownPanel.updates == [3, 2, 1])
        #expect(countdownPanel.dismissCalls == 1)
    }

    @Test func stopRecordingTransitionsToCompleted() async {
        let recorder = MockRecorderService()
        recorder.stopResult = .completed(makeSession())
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: MockRegionSelector(),
            countdownPanelFactory: { MockCountdownPanel() }
        )
        flow._setFlowStateForTesting(.recording)

        await flow.stopRecording()

        #expect(recorder.stopCalls == 1)
        switch flow.flowState {
        case .completed(let session):
            #expect(session.displayName == "Region 1280x720")
            #expect(abs(session.duration - 4.2) < 0.0001)
        default:
            Issue.record("Expected completed state, got \(flow.flowState)")
        }
    }

    @Test func stopRecordingUnexpectedFinalStateIsFailure() async {
        let recorder = MockRecorderService()
        recorder.stopResult = .ready
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: MockRegionSelector(),
            countdownPanelFactory: { MockCountdownPanel() }
        )
        flow._setFlowStateForTesting(.recording)

        await flow.stopRecording()

        switch flow.flowState {
        case .failed(let message):
            #expect(message == "Unexpected state after stopping")
        default:
            Issue.record("Expected failed state, got \(flow.flowState)")
        }
    }

    @Test func resetReturnsToConfiguringAndResetsRecorder() {
        let recorder = MockRecorderService()
        let flow = RecorderFlowController(
            recorder: recorder,
            regionSelector: MockRegionSelector(),
            countdownPanelFactory: { MockCountdownPanel() }
        )
        flow._setFlowStateForTesting(.failed("x"))

        flow.reset()

        #expect(flow.flowState == .configuring)
        #expect(flow.recordingDuration == 0)
        #expect(recorder.resetCalls == 1)
    }
}
