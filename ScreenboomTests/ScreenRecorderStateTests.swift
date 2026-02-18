import Testing
import Foundation
@preconcurrency import ScreenCaptureKit
@testable import Screenboom

@MainActor
struct ScreenRecorderStateTests {
    @Test func captureModeIdsMatchRawValues() {
        #expect(CaptureMode.display.id == "Display")
        #expect(CaptureMode.window.id == "Window")
        #expect(CaptureMode.region.id == "Region")
    }

    @Test func screenRecorderStateEqualityIgnoresPayloadValues() {
        let completedA = ScreenRecorder.State.completed(
            RecordingSession(
                videoURL: URL(fileURLWithPath: "/tmp/a.mp4"),
                cursorMetadataURL: nil,
                duration: 1,
                sourceSize: CGSize(width: 100, height: 100),
                frameRate: 30,
                displayName: "A",
                startDate: Date(timeIntervalSince1970: 1)
            )
        )
        let completedB = ScreenRecorder.State.completed(
            RecordingSession(
                videoURL: URL(fileURLWithPath: "/tmp/b.mp4"),
                cursorMetadataURL: nil,
                duration: 9,
                sourceSize: CGSize(width: 400, height: 300),
                frameRate: 60,
                displayName: "B",
                startDate: Date(timeIntervalSince1970: 999)
            )
        )
        #expect(completedA == completedB)
        #expect(ScreenRecorder.State.failed("x") == ScreenRecorder.State.failed("y"))
        #expect(ScreenRecorder.State.ready != ScreenRecorder.State.recording)
    }

    @MainActor
    @Test func startRecordingWhenNotReadyIsNoOp() async {
        let recorder = ScreenRecorder()
        #expect(recorder.state == .idle)

        await recorder.startRecording()

        #expect(recorder.state == .idle)
    }

    @MainActor
    @Test func stopRecordingWhenNotRecordingIsNoOp() async {
        let recorder = ScreenRecorder()
        #expect(recorder.state == .idle)

        await recorder.stopRecording()

        #expect(recorder.state == .idle)
    }

    @MainActor
    @Test func resetMovesRecorderToReady() {
        let recorder = ScreenRecorder()
        #expect(recorder.state == .idle)

        recorder.reset()

        #expect(recorder.state == .ready)
        #expect(recorder.recordingDuration == 0)
    }

}
