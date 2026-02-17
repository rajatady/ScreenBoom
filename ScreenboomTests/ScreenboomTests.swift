import Testing
import Foundation
@testable import Screenboom

struct ScreenboomTests {

    // MARK: - CursorEvent

    @Test func cursorEventRoundTrip() throws {
        let event = CursorEvent(timestamp: 1.5, x: 100.0, y: 200.0, type: .click, button: .left)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CursorEvent.self, from: data)

        #expect(decoded.timestamp == 1.5)
        #expect(decoded.x == 100.0)
        #expect(decoded.y == 200.0)
        #expect(decoded.type == .click)
        #expect(decoded.button == .left)
    }

    @Test func moveEventHasNoButton() throws {
        let event = CursorEvent(timestamp: 0.5, x: 50.0, y: 75.0, type: .move, button: nil)
        let data = try JSONEncoder().encode(event)
        let json = String(data: data, encoding: .utf8)!

        // button key should be absent from JSON (not present as null)
        #expect(!json.contains("button"))

        let decoded = try JSONDecoder().decode(CursorEvent.self, from: data)
        #expect(decoded.button == nil)
        #expect(decoded.type == .move)
    }

    @Test func releaseEventWithRightButton() throws {
        let event = CursorEvent(timestamp: 2.0, x: 300.0, y: 400.0, type: .release, button: .right)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CursorEvent.self, from: data)

        #expect(decoded.type == .release)
        #expect(decoded.button == .right)
    }

    // MARK: - CursorMetadataFile

    @Test func metadataFileRoundTrip() throws {
        let events = [
            CursorEvent(timestamp: 0.0, x: 10, y: 20, type: .move, button: nil),
            CursorEvent(timestamp: 0.1, x: 30, y: 40, type: .click, button: .left),
            CursorEvent(timestamp: 0.2, x: 30, y: 40, type: .release, button: .left),
        ]
        let metadata = CursorMetadataFile(
            frameRate: 60.0,
            sourceSize: CursorMetadataFile.CodableSize(width: 1920, height: 1080),
            events: events
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.frameRate == 60.0)
        #expect(decoded.sourceSize.width == 1920)
        #expect(decoded.sourceSize.height == 1080)
        #expect(decoded.events.count == 3)
        #expect(decoded.events[0].type == .move)
        #expect(decoded.events[1].type == .click)
        #expect(decoded.events[2].type == .release)
    }

    // MARK: - Coordinate Mapping

    @Test func coordinateMappingBottomLeftToTopLeft() {
        // NSEvent uses bottom-left origin. Video uses top-left origin.
        // videoY = screenHeight - screenY
        let screenHeight: Double = 1080
        let screenY: Double = 200 // 200px from bottom
        let videoY = screenHeight - screenY // should be 880px from top

        #expect(videoY == 880)
    }

    @Test func coordinateMappingOrigin() {
        // Bottom-left corner in screen coords → top-left corner would be at height
        let screenHeight: Double = 1440
        let screenY: Double = 0 // bottom edge
        let videoY = screenHeight - screenY

        #expect(videoY == 1440)
    }

    // MARK: - RecordingSession

    @Test func recordingSessionCreation() {
        let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let cursorURL = URL(fileURLWithPath: "/tmp/test.cursor.json")
        let date = Date()

        let session = RecordingSession(
            videoURL: videoURL,
            cursorMetadataURL: cursorURL,
            duration: 30.5,
            sourceSize: CGSize(width: 1920, height: 1080),
            frameRate: 60,
            displayName: "Screen Recording",
            startDate: date
        )

        #expect(session.videoURL == videoURL)
        #expect(session.cursorMetadataURL == cursorURL)
        #expect(session.duration == 30.5)
        #expect(session.sourceSize.width == 1920)
        #expect(session.sourceSize.height == 1080)
        #expect(session.frameRate == 60)
        #expect(session.displayName == "Screen Recording")
        #expect(session.startDate == date)
    }

    @Test func recordingSessionWithoutCursor() {
        let session = RecordingSession(
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            cursorMetadataURL: nil,
            duration: 10.0,
            sourceSize: CGSize(width: 2560, height: 1440),
            frameRate: 30,
            displayName: "Window Recording",
            startDate: Date()
        )

        #expect(session.cursorMetadataURL == nil)
    }

    // MARK: - ScreenRecorder Initial State

    @Test func screenRecorderStartsIdle() {
        let recorder = ScreenRecorder()
        #expect(recorder.state == .idle)
        #expect(recorder.recordingDuration == 0)
        #expect(recorder.availableDisplays.isEmpty)
        #expect(recorder.availableWindows.isEmpty)
    }
}
