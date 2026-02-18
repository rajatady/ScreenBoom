import Testing
import Foundation
@preconcurrency import ScreenCaptureKit
@testable import Screenboom

// MARK: - FlowController Expanded Tests
// Covers: canStart logic, captureMode didSet edge cases, refreshWindows,
// teardown safety, config sync to recorder, region cancel callback,
// initiateRecording guards, duration timer concept.

@MainActor
struct RecorderFlowControllerExpandedTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Shared Mocks (same as RecorderFlowControllerTests)
    // ─────────────────────────────────────────────────────────────────

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
                displayName: "Mock",
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
        func refreshWindows() async { refreshCalls += 1 }
        func startRecording() async { startCalls += 1; state = startResult }
        func stopRecording() async { stopCalls += 1; state = stopResult }
        func reset() { resetCalls += 1; state = .ready }
    }

    final class MockRegionSelector: RegionSelectorManaging {
        var startCalls = 0
        var forceCloseCalls = 0
        private var onSelected: ((CGRect, NSScreen) -> Void)?
        private var onCancelled: (() -> Void)?

        func startSelection(onSelected: @escaping (CGRect, NSScreen) -> Void, onCancelled: (() -> Void)?) {
            startCalls += 1
            self.onSelected = onSelected
            self.onCancelled = onCancelled
        }
        func forceClose() { forceCloseCalls += 1 }
        func emitSelection(_ rect: CGRect, screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) {
            onSelected?(rect, screen)
        }
        func emitCancel() { onCancelled?() }
    }

    final class MockCountdownPanel: CountdownPanelManaging {
        var showCalls = 0
        var dismissCalls = 0
        var updates: [Int] = []
        func show(on screen: NSScreen) { showCalls += 1 }
        func updateCount(_ count: Int) { updates.append(count) }
        func dismiss() { dismissCalls += 1 }
    }

    private func makeFlow(
        recorder: MockRecorderService? = nil,
        region: MockRegionSelector? = nil,
        countdown: MockCountdownPanel? = nil
    ) -> (flow: RecorderFlowController, recorder: MockRecorderService, region: MockRegionSelector, countdown: MockCountdownPanel) {
        let rec = recorder ?? MockRecorderService()
        let reg = region ?? MockRegionSelector()
        let cd = countdown ?? MockCountdownPanel()
        let flow = RecorderFlowController(
            recorder: rec,
            regionSelector: reg,
            countdownPanelFactory: { cd }
        )
        return (flow, rec, reg, cd)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - canStart Logic
    // ─────────────────────────────────────────────────────────────────

    @Test func canStartIsFalseWhenNotConfiguring() {
        let (flow, _, _, _) = makeFlow()
        // idle state → canStart should be false
        #expect(!flow.canStart)
    }

    @Test func canStartIsTrueForDisplayModeWhenConfiguring() {
        let (flow, _, _, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display
        #expect(flow.canStart)
    }

    @Test func canStartIsTrueForWindowModeWhenConfiguring() {
        let (flow, _, _, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        // Switch away from region first to avoid auto-selection trigger
        flow.captureMode = .window
        #expect(flow.canStart)
    }

    @Test func canStartIsFalseForRegionModeWithoutSelection() {
        let (flow, _, _, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region
        // Region mode triggers selectingRegion, but no selection emitted yet
        // canStart requires configuring state AND region selected
        #expect(!flow.canStart)
    }

    @Test func canStartIsTrueForRegionModeWithSelection() {
        let (flow, _, region, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region
        region.emitSelection(CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(flow.canStart)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - captureMode didSet Edge Cases
    // ─────────────────────────────────────────────────────────────────

    @Test func switchingToRegionWithExistingSelectionDoesNotRetrigger() {
        let (flow, _, region, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow._setSelectedRegionForTesting(CGRect(x: 0, y: 0, width: 640, height: 480))

        flow.captureMode = .region

        // Should NOT trigger region selection since selectedRegion is already set
        #expect(region.startCalls == 0)
        #expect(flow.flowState == .configuring)
    }

    @Test func switchingFromRegionToDisplayWhileNotSelectingDoesNotForceClose() {
        let (flow, _, region, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display
        // Not in selectingRegion state, so forceClose should NOT be called
        let closeCountBefore = region.forceCloseCalls
        flow.captureMode = .display // same mode, no change
        #expect(region.forceCloseCalls == closeCountBefore)
    }

    @Test func settingSameCaptureModeDoesNothing() {
        let (flow, _, region, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display

        // Set again — didSet guard should prevent action
        flow.captureMode = .display
        #expect(region.startCalls == 0)
        #expect(region.forceCloseCalls == 0)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - refreshWindows
    // ─────────────────────────────────────────────────────────────────

    @Test func refreshWindowsDelegatesToRecorder() async {
        let (flow, recorder, _, _) = makeFlow()
        await flow.refreshWindows()
        #expect(recorder.refreshCalls == 1)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Region Cancel Callback
    // ─────────────────────────────────────────────────────────────────

    @Test func regionCancelCallbackReturnsToConfiguring() {
        let (flow, _, region, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region
        #expect(flow.flowState == .selectingRegion)

        region.emitCancel()

        #expect(flow.flowState == .configuring)
        #expect(flow.selectedRegion == nil)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - initiateRecording Guards
    // ─────────────────────────────────────────────────────────────────

    @Test func initiateRecordingDoesNothingWhenCanStartIsFalse() {
        let (flow, recorder, _, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region
        // No region selected → canStart is false (flowState is selectingRegion)

        flow.initiateRecording()
        #expect(recorder.startCalls == 0)
    }

    @Test func initiateRecordingDoesNothingWhenRecording() {
        let (flow, recorder, _, _) = makeFlow()
        flow._setFlowStateForTesting(.recording)

        flow.initiateRecording()
        #expect(recorder.startCalls == 0)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Config Sync to Recorder
    // ─────────────────────────────────────────────────────────────────

    @Test func beginActualRecordingSyncsAllConfigToRecorder() async {
        let recorder = MockRecorderService()
        recorder.startResult = .recording
        let countdown = MockCountdownPanel()
        let (flow, _, _, _) = makeFlow(recorder: recorder, countdown: countdown)

        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display
        flow.frameRate = 30
        flow.enableCursorTracking = false
        flow._setSelectedRegionForTesting(CGRect(x: 10, y: 20, width: 300, height: 200))

        // Use synchronous scheduler to skip countdown
        flow.countdownStepScheduler = { _, action in action() }
        flow.initiateRecording()
        try? await Task.sleep(for: .milliseconds(50))

        // Verify all config was synced to the recorder service
        #expect(recorder.captureMode == .display)
        #expect(recorder.frameRate == 30)
        #expect(recorder.enableCursorTracking == false)
        #expect(recorder.selectedRegion == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(recorder.startCalls == 1)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Teardown Safety
    // ─────────────────────────────────────────────────────────────────

    @Test func teardownPreventsRegionCallbackFromFiring() {
        let (flow, _, region, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .region
        #expect(flow.flowState == .selectingRegion)

        flow.teardown()

        // Even if region callback fires after teardown, state should not change
        let stateAfterTeardown = flow.flowState
        region.emitSelection(CGRect(x: 0, y: 0, width: 500, height: 300))
        // The callback checks isTearingDown and returns early
        #expect(flow.selectedRegion == nil)
    }

    @Test func teardownCleansUpTimersAndPanels() {
        let countdown = MockCountdownPanel()
        let (flow, _, region, _) = makeFlow(countdown: countdown)

        flow._setFlowStateForTesting(.countdown(2))
        // _setFlowStateForTesting bypasses normal flow, so inject the countdown panel manually
        flow._setCountdownPanelForTesting(countdown)
        flow.teardown()

        // Should have dismissed countdown and force-closed region
        #expect(countdown.dismissCalls >= 1)
        #expect(region.forceCloseCalls >= 1)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Stop Guards
    // ─────────────────────────────────────────────────────────────────

    @Test func stopRecordingIgnoredWhenNotRecording() async {
        let (flow, recorder, _, _) = makeFlow()
        flow._setFlowStateForTesting(.configuring)

        await flow.stopRecording()
        #expect(recorder.stopCalls == 0)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Recording Start Failure
    // ─────────────────────────────────────────────────────────────────

    @Test func recordingStartFailureTransitionsToFailed() async {
        let recorder = MockRecorderService()
        recorder.startResult = .failed("No display")
        let countdown = MockCountdownPanel()
        let (flow, _, _, _) = makeFlow(recorder: recorder, countdown: countdown)

        flow._setFlowStateForTesting(.configuring)
        flow.captureMode = .display
        flow.countdownStepScheduler = { _, action in action() }
        flow.initiateRecording()
        try? await Task.sleep(for: .milliseconds(50))

        switch flow.flowState {
        case .failed(let msg):
            #expect(msg == "No display")
        default:
            Issue.record("Expected failed state, got \(flow.flowState)")
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Permission Populates Displays/Windows
    // ─────────────────────────────────────────────────────────────────

    @Test func permissionPopulatesAvailableDisplaysAndWindows() async {
        let recorder = MockRecorderService()
        recorder.permissionResult = .ready
        // We can't create real SCDisplay/SCWindow, but we verify the plumbing
        let (flow, _, _, _) = makeFlow(recorder: recorder)

        await flow.requestPermission()

        #expect(flow.flowState == .configuring)
        // Displays/windows come from recorder — both empty in mock
        #expect(flow.availableDisplays.isEmpty)
        #expect(flow.availableWindows.isEmpty)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Reset Clears Duration
    // ─────────────────────────────────────────────────────────────────

    @Test func resetClearsDurationAndReturnsToConfiguring() {
        let (flow, recorder, _, _) = makeFlow()
        flow._setFlowStateForTesting(.recording)

        flow.reset()

        #expect(flow.flowState == .configuring)
        #expect(flow.recordingDuration == 0)
        #expect(recorder.resetCalls == 1)
    }
}
