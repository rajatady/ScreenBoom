import Testing
import Foundation
@testable import Screenboom

// MARK: - Recording Models Expanded Tests
// Covers: CursorEvent all types, CursorMetadataFile round-trip with events,
// RecordingSession fields, metadata backward compatibility.

struct RecordingModelsExpandedTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - CursorEvent
    // ─────────────────────────────────────────────────────────────────

    @Test func cursorEventAllTypesRoundTrip() throws {
        let events: [CursorEvent] = [
            CursorEvent(timestamp: 0.1, x: 100, y: 200, type: .move, button: nil),
            CursorEvent(timestamp: 0.5, x: 150, y: 180, type: .click, button: .left),
            CursorEvent(timestamp: 0.8, x: 150, y: 180, type: .release, button: .left),
            CursorEvent(timestamp: 1.0, x: 300, y: 100, type: .scroll, button: nil),
            CursorEvent(timestamp: 1.2, x: 300, y: 100, type: .keyDown, button: nil),
            CursorEvent(timestamp: 1.5, x: 400, y: 250, type: .click, button: .right),
        ]

        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([CursorEvent].self, from: data)

        #expect(decoded.count == 6)
        #expect(decoded[0].type == .move)
        #expect(decoded[0].button == nil)
        #expect(decoded[1].type == .click)
        #expect(decoded[1].button == .left)
        #expect(decoded[2].type == .release)
        #expect(decoded[3].type == .scroll)
        #expect(decoded[4].type == .keyDown)
        #expect(decoded[5].button == .right)
    }

    @Test func cursorEventTimestampAndCoordsPreserved() throws {
        let event = CursorEvent(timestamp: 3.14159, x: 1920.5, y: 1080.25, type: .move, button: nil)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CursorEvent.self, from: data)

        #expect(abs(decoded.timestamp - 3.14159) < 0.00001)
        #expect(abs(decoded.x - 1920.5) < 0.001)
        #expect(abs(decoded.y - 1080.25) < 0.001)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - CursorMetadataFile
    // ─────────────────────────────────────────────────────────────────

    @Test func metadataFileRoundTripWithEvents() throws {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            captureOrigin: .init(x: 100, y: 200),
            displayHeight: 1080,
            backingScaleFactor: 2.0,
            events: [
                CursorEvent(timestamp: 0.1, x: 500, y: 300, type: .move, button: nil),
                CursorEvent(timestamp: 0.5, x: 600, y: 400, type: .click, button: .left),
            ]
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.frameRate == 60)
        #expect(decoded.sourceSize.width == 1920)
        #expect(decoded.sourceSize.height == 1080)
        #expect(decoded.captureOrigin?.x == 100)
        #expect(decoded.captureOrigin?.y == 200)
        #expect(decoded.displayHeight == 1080)
        #expect(decoded.backingScaleFactor == 2.0)
        #expect(decoded.events.count == 2)
        #expect(decoded.events[0].type == .move)
        #expect(decoded.events[1].type == .click)
    }

    @Test func metadataFileBackwardCompatWithoutOptionalFields() throws {
        // Simulate old format: no captureOrigin, displayHeight, backingScaleFactor
        let json = """
        {
            "version": 1,
            "frameRate": 30,
            "sourceSize": {"width": 1280, "height": 720},
            "events": [
                {"timestamp": 0.1, "x": 100, "y": 200, "type": "move"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.frameRate == 30)
        #expect(decoded.captureOrigin == nil)
        #expect(decoded.displayHeight == nil)
        #expect(decoded.backingScaleFactor == nil)
        #expect(decoded.events.count == 1)
    }

    @Test func metadataFileEmptyEventsRoundTrip() throws {
        let metadata = CursorMetadataFile(
            frameRate: 120,
            sourceSize: .init(width: 3840, height: 2160),
            events: []
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.frameRate == 120)
        #expect(decoded.sourceSize.width == 3840)
        #expect(decoded.events.isEmpty)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - RecordingSession
    // ─────────────────────────────────────────────────────────────────

    @Test func recordingSessionFieldsPreserved() {
        let session = RecordingSession(
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            cursorMetadataURL: URL(fileURLWithPath: "/tmp/test.cursor.json"),
            duration: 42.5,
            sourceSize: CGSize(width: 2560, height: 1440),
            frameRate: 60,
            displayName: "Region 1280×720",
            startDate: Date(timeIntervalSince1970: 1000000)
        )

        #expect(session.videoURL.lastPathComponent == "test.mp4")
        #expect(session.cursorMetadataURL?.lastPathComponent == "test.cursor.json")
        #expect(abs(session.duration - 42.5) < 0.001)
        #expect(session.sourceSize.width == 2560)
        #expect(session.sourceSize.height == 1440)
        #expect(session.frameRate == 60)
        #expect(session.displayName == "Region 1280×720")
    }

    @Test func recordingSessionWithNilCursorMetadata() {
        let session = RecordingSession(
            videoURL: URL(fileURLWithPath: "/tmp/no-cursor.mp4"),
            cursorMetadataURL: nil,
            duration: 10,
            sourceSize: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            displayName: "Display 3456×2234",
            startDate: Date()
        )

        #expect(session.cursorMetadataURL == nil)
        #expect(session.displayName == "Display 3456×2234")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - CursorTracker writeMetadata with Events
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    @Test func writeMetadataWithEventsRoundTrips() throws {
        let tracker = CursorTracker()
        tracker.captureOrigin = CGPoint(x: 50, y: 100)
        tracker.displayHeight = 1440
        tracker.backingScaleFactor = 2.0

        // We can't add events via tracking (requires permissions),
        // but we can verify the metadata structure with empty events
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-expanded-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try tracker.writeMetadata(
            to: outputURL,
            frameRate: 120,
            sourceSize: CGSize(width: 2560, height: 1440)
        )

        // Read back and verify
        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.frameRate == 120)
        #expect(decoded.sourceSize.width == 2560)
        #expect(decoded.sourceSize.height == 1440)
        #expect(decoded.captureOrigin?.x == 50)
        #expect(decoded.captureOrigin?.y == 100)
        #expect(decoded.displayHeight == 1440)
        #expect(decoded.backingScaleFactor == 2.0)
    }
}
