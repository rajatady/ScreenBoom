@preconcurrency import ScreenCaptureKit
import Foundation
import AppKit
import os

private let flowLog = Logger(subsystem: "com.trymagically.Screenboom", category: "RecorderFlow")

@MainActor
protocol RecorderServiceProtocol: AnyObject {
    var state: ScreenRecorder.State { get }
    var availableDisplays: [SCDisplay] { get }
    var availableWindows: [SCWindow] { get }

    var captureMode: CaptureMode { get set }
    var selectedDisplay: SCDisplay? { get set }
    var selectedWindow: SCWindow? { get set }
    var selectedRegion: CGRect? { get set }
    var frameRate: Int { get set }
    var enableCursorTracking: Bool { get set }

    func requestPermission() async
    func refreshWindows() async
    func startRecording() async
    func stopRecording() async
    func reset()
}

extension ScreenRecorder: RecorderServiceProtocol {}

@MainActor
protocol RegionSelectorManaging: AnyObject {
    func startSelection(onSelected: @escaping (CGRect) -> Void, onCancelled: (() -> Void)?)
    func forceClose()
}

extension RegionSelectorManager: RegionSelectorManaging {}

@MainActor
protocol CountdownPanelManaging: AnyObject {
    func show(on screen: NSScreen)
    func updateCount(_ count: Int)
    func dismiss()
}

extension CountdownPanelManager: CountdownPanelManaging {}

// MARK: - Recorder Flow Controller

/// Orchestrates the recording flow: permission -> configuration -> [region selection] -> countdown -> recording -> completion.
/// The view (RecorderBarView) reads state from here and delegates all actions.
/// ScreenRecorder is a private service — the view never touches it directly.
@Observable
final class RecorderFlowController {

    // MARK: - Flow State

    enum FlowState: Equatable {
        case idle
        case requestingPermission
        case configuring
        case selectingRegion
        case countdown(Int) // 3, 2, 1
        case preparing
        case recording
        case stopping
        case completed(RecordingSession)
        case failed(String)

        static func == (lhs: FlowState, rhs: FlowState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.requestingPermission, .requestingPermission),
                 (.configuring, .configuring), (.selectingRegion, .selectingRegion),
                 (.preparing, .preparing), (.recording, .recording),
                 (.stopping, .stopping):
                return true
            case (.countdown(let a), .countdown(let b)): return a == b
            case (.completed, .completed), (.failed, .failed): return true
            default: return false
            }
        }
    }

    // MARK: - Public State

    private(set) var flowState: FlowState = .idle
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var availableDisplays: [SCDisplay] = []
    private(set) var availableWindows: [SCWindow] = []

    var captureMode: CaptureMode = .display {
        didSet {
            guard oldValue != captureMode else { return }
            // Cancel ongoing region selection if switching away from region
            if oldValue == .region && flowState == .selectingRegion {
                regionSelector.forceClose()
                flowState = .configuring
            }
            // Auto-trigger region selection when switching to region with no selection
            if captureMode == .region && flowState == .configuring && selectedRegion == nil {
                beginRegionSelection()
            }
        }
    }

    var selectedDisplay: SCDisplay?
    var selectedWindow: SCWindow?
    private(set) var selectedRegion: CGRect?
    var frameRate: Int = 60
    var enableCursorTracking: Bool = true

    var canStart: Bool {
        flowState == .configuring && (captureMode != .region || selectedRegion != nil)
    }

    // MARK: - Private

    private let recorder: any RecorderServiceProtocol
    private let regionSelector: any RegionSelectorManaging
    private let countdownPanelFactory: () -> any CountdownPanelManaging
    private var countdownPanel: (any CountdownPanelManaging)?
    private var countdownTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartDate: Date?
    private var isTearingDown = false
    var countdownTickInterval: TimeInterval = 1.0
    var durationTickInterval: TimeInterval = 0.1
    var countdownStepScheduler: ((TimeInterval, @escaping () -> Void) -> Void)?

    init(
        recorder: any RecorderServiceProtocol = ScreenRecorder(),
        regionSelector: any RegionSelectorManaging = RegionSelectorManager(),
        countdownPanelFactory: @escaping () -> any CountdownPanelManaging = { CountdownPanelManager() }
    ) {
        self.recorder = recorder
        self.regionSelector = regionSelector
        self.countdownPanelFactory = countdownPanelFactory
    }

    // MARK: - Permission

    func requestPermission() async {
        flowState = .requestingPermission
        await recorder.requestPermission()

        availableDisplays = recorder.availableDisplays
        availableWindows = recorder.availableWindows
        selectedDisplay = recorder.selectedDisplay
        selectedWindow = recorder.selectedWindow

        if case .failed(let msg) = recorder.state {
            flowState = .failed(msg)
        } else {
            flowState = .configuring
        }
    }

    func refreshWindows() async {
        await recorder.refreshWindows()
        availableWindows = recorder.availableWindows
    }

    // MARK: - Region Selection

    func beginRegionSelection() {
        guard flowState == .configuring || flowState == .selectingRegion else { return }
        flowState = .selectingRegion
        regionSelector.startSelection(
            onSelected: { [weak self] rect in
                guard let self, !self.isTearingDown else { return }
                self.selectedRegion = rect
                self.flowState = .configuring
                flowLog.info("Region selected: \(rect.debugDescription)")
            },
            onCancelled: { [weak self] in
                guard let self, !self.isTearingDown else { return }
                self.flowState = .configuring
                flowLog.info("Region selection cancelled")
            }
        )
    }

    // MARK: - Countdown + Start

    func initiateRecording() {
        guard canStart else { return }
        startCountdown(from: 3)
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownPanel?.dismiss()
        countdownPanel = nil
        flowState = .configuring
    }

    private func startCountdown(from count: Int) {
        flowState = .countdown(count)

        if count == 3 {
            let screen = targetScreen()
            let panel = countdownPanelFactory()
            panel.show(on: screen)
            countdownPanel = panel
        }
        countdownPanel?.updateCount(count)

        let tick: () -> Void = { [weak self] in
            guard let self else { return }
            if count > 1 {
                self.startCountdown(from: count - 1)
            } else {
                self.countdownPanel?.dismiss()
                self.countdownPanel = nil
                self.beginActualRecording()
            }
        }

        if let countdownStepScheduler {
            countdownStepScheduler(countdownTickInterval, tick)
            return
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: countdownTickInterval, repeats: false) { _ in
            Task { @MainActor in
                tick()
            }
        }
    }

    private func beginActualRecording() {
        // Sync configuration to recorder service
        recorder.captureMode = captureMode
        recorder.selectedDisplay = selectedDisplay
        recorder.selectedWindow = selectedWindow
        recorder.selectedRegion = selectedRegion
        recorder.frameRate = frameRate
        recorder.enableCursorTracking = enableCursorTracking

        flowState = .preparing

        Task {
            await recorder.startRecording()

            switch recorder.state {
            case .recording:
                flowState = .recording
                recordingStartDate = Date()
                recordingDuration = 0
                startDurationTimer()
                flowLog.info("Recording started")
            case .failed(let msg):
                flowState = .failed(msg)
                flowLog.error("Recording failed: \(msg)")
            default:
                break
            }
        }
    }

    // MARK: - Stop

    func stopRecording() async {
        guard flowState == .recording else { return }
        flowState = .stopping

        durationTimer?.invalidate()
        durationTimer = nil

        await recorder.stopRecording()

        switch recorder.state {
        case .completed(let session):
            flowState = .completed(session)
            flowLog.info("Recording completed: \(session.duration)s")
        case .failed(let msg):
            flowState = .failed(msg)
            flowLog.error("Recording stop failed: \(msg)")
        default:
            flowState = .failed("Unexpected state after stopping")
        }
    }

    // MARK: - Reset

    func reset() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        countdownPanel?.dismiss()
        countdownPanel = nil
        recorder.reset()
        recordingDuration = 0
        flowState = .configuring
    }

    /// Called by RecorderPanelManager before discarding this controller.
    /// Cleans up all resources without firing callbacks back into the view.
    func teardown() {
        isTearingDown = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        countdownPanel?.dismiss()
        countdownPanel = nil
        regionSelector.forceClose()
    }

    // MARK: - Helpers

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: durationTickInterval, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            self.recordingDuration = Date().timeIntervalSince(start)
        }
    }

    /// Determine which screen to show the countdown on.
    private func targetScreen() -> NSScreen {
        switch captureMode {
        case .display:
            if let display = selectedDisplay {
                let dx = CGFloat(display.frame.origin.x)
                let dy = CGFloat(display.frame.origin.y)
                if let screen = NSScreen.screens.first(where: {
                    abs($0.frame.origin.x - dx) < 2 && abs($0.frame.origin.y - dy) < 2
                }) { return screen }
            }
        case .window:
            if let window = selectedWindow {
                let mid = CGPoint(x: window.frame.midX, y: window.frame.midY)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(mid) }) {
                    return screen
                }
            }
        case .region:
            // selectedRegion is display-relative, so match screen via the selected display
            if let display = selectedDisplay ?? availableDisplays.first {
                if let screen = NSScreen.screens.first(where: {
                    let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
                    return id == display.displayID
                }) { return screen }
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

#if DEBUG
    func _setFlowStateForTesting(_ state: FlowState) {
        flowState = state
    }

    func _setSelectedRegionForTesting(_ region: CGRect?) {
        selectedRegion = region
    }
#endif
}
