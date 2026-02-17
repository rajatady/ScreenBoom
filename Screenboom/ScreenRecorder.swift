@preconcurrency import ScreenCaptureKit
import AVFoundation
import AppKit
import os

private let recLog = Logger(subsystem: "com.trymagically.Screenboom", category: "Recorder")

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable, Identifiable {
    case display = "Display"
    case window = "Window"
    case region = "Region"
    var id: String { rawValue }
}

// MARK: - Screen Recorder

@Observable
final class ScreenRecorder {

    enum State: Equatable {
        case idle
        case requestingPermission
        case ready
        case preparing
        case recording
        case stopping
        case completed(RecordingSession)
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.requestingPermission, .requestingPermission),
                 (.ready, .ready), (.preparing, .preparing), (.recording, .recording),
                 (.stopping, .stopping):
                return true
            case (.completed, .completed), (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var availableDisplays: [SCDisplay] = []
    private(set) var availableWindows: [SCWindow] = []
    private(set) var recordingDuration: TimeInterval = 0

    var captureMode: CaptureMode = .display
    var selectedDisplay: SCDisplay?
    var selectedWindow: SCWindow?
    var selectedRegion: CGRect?
    var frameRate: Int = 60
    var enableCursorTracking: Bool = true
    var includeCamera: Bool = false

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var streamDelegate: StreamDelegate?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var cursorTracker: CursorTracker?
    private var durationTimer: Timer?
    private var recordingStartDate: Date?
    private var outputURL: URL?
    private var sourceSize: CGSize = .zero

    // MARK: - Permission & Content Discovery

    func requestPermission() async {
        state = .requestingPermission
        do {
            let content = try await SCShareableContent.current
            availableDisplays = content.displays
            availableWindows = content.windows.filter { $0.isOnScreen && $0.frame.width > 100 && $0.frame.height > 100 }
            if selectedDisplay == nil { selectedDisplay = availableDisplays.first }
            if selectedWindow == nil { selectedWindow = availableWindows.first }
            state = .ready
        } catch {
            state = .failed("Screen recording permission denied. Grant access in System Settings → Privacy & Security → Screen & System Audio Recording.")
        }
    }

    func refreshWindows() async {
        do {
            let content = try await SCShareableContent.current
            availableWindows = content.windows.filter { $0.isOnScreen && $0.frame.width > 100 && $0.frame.height > 100 }
        } catch {}
    }

    // MARK: - Start Recording

    func startRecording() async {
        guard state == .ready else { return }
        state = .preparing

        let tempDir = FileManager.default.temporaryDirectory
        let videoFile = tempDir.appendingPathComponent("screenboom-\(UUID().uuidString).mp4")
        outputURL = videoFile

        do {
            let filter: SCContentFilter
            let capturedSize: CGSize

            switch captureMode {
            case .display:
                guard let display = selectedDisplay else {
                    state = .failed("No display selected")
                    return
                }
                let excludedApps = try await SCShareableContent.current.applications.filter {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
                capturedSize = CGSize(width: display.width, height: display.height)
            case .window:
                guard let window = selectedWindow else {
                    state = .failed("No window selected")
                    return
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                capturedSize = window.frame.size
            case .region:
                guard let region = selectedRegion else {
                    state = .failed("No region selected")
                    return
                }
                // Region mode uses display filter with sourceRect
                guard let display = selectedDisplay ?? availableDisplays.first else {
                    state = .failed("No display available")
                    return
                }
                let excludedApps = try await SCShareableContent.current.applications.filter {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
                capturedSize = CGSize(width: region.width, height: region.height)
            }

            sourceSize = capturedSize

            let config = SCStreamConfiguration()
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA

            if captureMode == .region, let region = selectedRegion {
                // ScreenCaptureKit uses Quartz display coordinates (top-left origin)
                config.sourceRect = region
                config.width = Int(region.width)
                config.height = Int(region.height)
            } else {
                config.width = Int(capturedSize.width)
                config.height = Int(capturedSize.height)
            }

            // AVAssetWriter
            let writer = try AVAssetWriter(outputURL: videoFile, fileType: .mp4)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(capturedSize.width),
                AVVideoHeightKey: Int(capturedSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 20_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: frameRate
                ] as [String: Any]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)

            assetWriter = writer
            videoInput = input

            let output = StreamOutput(writerInput: input, assetWriter: writer)
            streamOutput = output

            // Stream delegate to catch errors
            let delegate = StreamDelegate { [weak self] error in
                self?.handleStreamError(error)
            }
            streamDelegate = delegate

            let captureStream = SCStream(filter: filter, configuration: config, delegate: delegate)
            try captureStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.screenboom.capture", qos: .userInteractive))
            stream = captureStream

            if enableCursorTracking {
                let tracker = CursorTracker()
                // Capture display height + Retina factor for Cocoa→Quartz coordinate conversion
                tracker.displayHeight = NSScreen.main?.frame.size.height ?? 0
                tracker.backingScaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0
                // Set capture origin so cursor coordinates can be mapped to video coordinates
                switch captureMode {
                case .display:
                    if let display = selectedDisplay {
                        tracker.captureOrigin = CGPoint(x: CGFloat(display.frame.origin.x), y: CGFloat(display.frame.origin.y))
                        // DEBUG: Log all coordinate system values to diagnose cursor offset
                        let screenH = NSScreen.main?.frame.size.height ?? 0
                        recLog.info("""
                        [CURSOR DEBUG] Display mode coordinate info:
                          SCDisplay.width=\(display.width), SCDisplay.height=\(display.height)
                          SCDisplay.frame=\(display.frame.debugDescription)
                          capturedSize=\(capturedSize.debugDescription)
                          captureOrigin=(\(display.frame.origin.x), \(display.frame.origin.y))
                          NSScreen.main.frame=\(NSScreen.main?.frame.debugDescription ?? "nil")
                          NSScreen.main.frame.height=\(screenH)
                          NSScreen.main.visibleFrame=\(NSScreen.main?.visibleFrame.debugDescription ?? "nil")
                          NSScreen.main.backingScaleFactor=\(NSScreen.main?.backingScaleFactor ?? 0)
                          coordSystemCheck: sourceH + 2*originY = \(capturedSize.height + 2 * Double(display.frame.origin.y)), displayH = \(screenH)
                          expectedError = sourceH + 2*originY - displayH = \(capturedSize.height + 2 * Double(display.frame.origin.y) - screenH)
                          allScreens=\(NSScreen.screens.map { "frame=\($0.frame.debugDescription) scale=\($0.backingScaleFactor)" })
                        """)
                    }
                case .window:
                    if let window = selectedWindow {
                        tracker.captureOrigin = window.frame.origin
                        let screenH = NSScreen.main?.frame.size.height ?? 0
                        recLog.info("""
                        [CURSOR DEBUG] Window mode coordinate info:
                          SCWindow.frame=\(window.frame.debugDescription)
                          SCWindow.title=\(window.title ?? "nil")
                          capturedSize=\(capturedSize.debugDescription)
                          captureOrigin=(\(window.frame.origin.x), \(window.frame.origin.y))
                          NSScreen.main.frame=\(NSScreen.main?.frame.debugDescription ?? "nil")
                          NSScreen.main.frame.height=\(screenH)
                          NSScreen.main.backingScaleFactor=\(NSScreen.main?.backingScaleFactor ?? 0)
                          coordSystemCheck: sourceH + 2*originY = \(capturedSize.height + 2 * window.frame.origin.y), displayH = \(screenH)
                          expectedError = sourceH + 2*originY - displayH = \(capturedSize.height + 2 * window.frame.origin.y - screenH)
                        """)
                    }
                case .region:
                    if let region = selectedRegion {
                        // region is display-relative top-left coords (for SCK sourceRect).
                        // Cursor events (NSEvent.mouseLocation) are in global Cocoa coords (bottom-left).
                        // Convert region origin to global Cocoa coords for cursor offset math.
                        let display = selectedDisplay ?? availableDisplays.first
                        let matchedScreen: NSScreen = {
                            if let d = display {
                                return NSScreen.screens.first(where: {
                                    let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
                                    return id == d.displayID
                                }) ?? NSScreen.main ?? NSScreen.screens[0]
                            }
                            return NSScreen.main ?? NSScreen.screens[0]
                        }()
                        let sf = matchedScreen.frame
                        tracker.captureOrigin = CGPoint(
                            x: sf.origin.x + region.origin.x,
                            y: sf.origin.y + (sf.height - region.origin.y - region.height)
                        )
                        recLog.info("""
                        [REGION DEBUG] Region cursor tracking:
                          selectedRegion (display-relative top-left)=\(region.debugDescription)
                          matchedScreen.frame=\(sf.debugDescription)
                          captureOrigin (global Cocoa bottom-left)=(\(sf.origin.x + region.origin.x), \(sf.origin.y + (sf.height - region.origin.y - region.height)))
                          capturedSize=\(capturedSize.debugDescription)
                          config.sourceRect=\(region.debugDescription)
                          backingScaleFactor=\(matchedScreen.backingScaleFactor)
                        """)
                    }
                }
                cursorTracker = tracker
                tracker.startTracking()
            }

            writer.startWriting()
            try await captureStream.startCapture()

            recordingStartDate = Date()
            recordingDuration = 0
            state = .recording

            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            state = .failed("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func handleStreamError(_ error: any Error) {
        print("SCStream error: \(error.localizedDescription)")
        if state == .recording {
            Task { await stopRecording() }
        }
    }

    // MARK: - Stop Recording

    func stopRecording() async {
        guard state == .recording else { return }
        state = .stopping

        durationTimer?.invalidate()
        durationTimer = nil

        cursorTracker?.stopTracking()

        do {
            try await stream?.stopCapture()
        } catch {
            print("Stream stop error: \(error)")
        }
        stream = nil
        streamDelegate = nil

        // Give writer a moment to flush any pending frames
        try? await Task.sleep(for: .milliseconds(100))

        videoInput?.markAsFinished()
        await assetWriter?.finishWriting()

        guard let videoURL = outputURL, assetWriter?.status == .completed else {
            let writerStatus = assetWriter?.status.rawValue ?? -1
            let errorMsg = assetWriter?.error?.localizedDescription ?? "Writer status: \(writerStatus), no frames may have been captured"
            state = .failed("Recording failed: \(errorMsg)")
            return
        }

        var cursorURL: URL?
        if enableCursorTracking, let tracker = cursorTracker {
            let metadataURL = videoURL.deletingPathExtension().appendingPathExtension("cursor.json")
            do {
                try tracker.writeMetadata(to: metadataURL, frameRate: Double(frameRate), sourceSize: sourceSize)
                cursorURL = metadataURL
            } catch {
                print("Failed to write cursor metadata: \(error)")
            }
        }

        let session = RecordingSession(
            videoURL: videoURL,
            cursorMetadataURL: cursorURL,
            duration: recordingDuration,
            sourceSize: sourceSize,
            frameRate: Double(frameRate),
            displayName: {
                switch captureMode {
                case .display: return "Screen Recording"
                case .window: return selectedWindow?.title ?? "Window Recording"
                case .region:
                    if let r = selectedRegion {
                        return "Region \(Int(r.width))\u{00D7}\(Int(r.height))"
                    }
                    return "Region Recording"
                }
            }(),
            startDate: recordingStartDate ?? Date()
        )

        state = .completed(session)

        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        cursorTracker = nil
    }

    func reset() {
        state = .ready
        recordingDuration = 0
    }
}

// MARK: - Stream Delegate (catches stream errors)

final class StreamDelegate: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let onError: (any Error) -> Void

    init(onError: @escaping (any Error) -> Void) {
        self.onError = onError
        super.init()
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onError(error)
    }
}

// MARK: - Stream Output (captures sample buffers on queue)

final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writerInput: AVAssetWriterInput
    private let assetWriter: AVAssetWriter
    private var sessionStarted = false

    init(writerInput: AVAssetWriterInput, assetWriter: AVAssetWriter) {
        self.writerInput = writerInput
        self.assetWriter = assetWriter
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Critical: only process frames that have actual pixel data.
        // ScreenCaptureKit sends status-only buffers without image data that
        // corrupt the writer if appended.
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        guard assetWriter.status == .writing else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }
    }
}
