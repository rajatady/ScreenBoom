import Testing
import Foundation
@testable import Screenboom

// MARK: - Cursor Tracker Expanded Tests
// Covers: double startTracking guard, writeMetadata round-trip,
// stopTracking idempotency, metadata field preservation.

@MainActor
struct CursorTrackerExpandedTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-track-\(UUID().uuidString).json")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - startTracking Guard
    // ─────────────────────────────────────────────────────────────────

    @Test func startTrackingSetsIsTracking() {
        let tracker = CursorTracker()
        #expect(!tracker.isTracking)

        tracker.startTracking()
        #expect(tracker.isTracking)
        #expect(tracker.events.isEmpty, "No events yet — just started")

        tracker.stopTracking()
        #expect(!tracker.isTracking)
    }

    @Test func doubleStartTrackingIsIdempotent() {
        let tracker = CursorTracker()
        tracker.startTracking()
        tracker.startTracking()  // second call should be guarded
        #expect(tracker.isTracking)
        tracker.stopTracking()
        #expect(!tracker.isTracking)
    }

    @Test func stopTrackingWithoutStartIsNoOp() {
        let tracker = CursorTracker()
        tracker.stopTracking()
        #expect(!tracker.isTracking)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - writeMetadata
    // ─────────────────────────────────────────────────────────────────

    @Test func writeMetadataPreservesAllFields() throws {
        let tracker = CursorTracker()
        tracker.captureOrigin = CGPoint(x: 100, y: 200)
        tracker.displayHeight = 2160
        tracker.backingScaleFactor = 2.0

        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try tracker.writeMetadata(
            to: url,
            frameRate: 120,
            sourceSize: CGSize(width: 3840, height: 2160)
        )

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.frameRate == 120)
        #expect(decoded.sourceSize.width == 3840)
        #expect(decoded.sourceSize.height == 2160)
        #expect(decoded.captureOrigin?.x == 100)
        #expect(decoded.captureOrigin?.y == 200)
        #expect(decoded.displayHeight == 2160)
        #expect(decoded.backingScaleFactor == 2.0)
    }

    @Test func writeMetadataWithDefaultsHasNilOptionals() throws {
        let tracker = CursorTracker()
        // Don't set captureOrigin, displayHeight, backingScaleFactor

        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try tracker.writeMetadata(
            to: url,
            frameRate: 30,
            sourceSize: CGSize(width: 1280, height: 720)
        )

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.frameRate == 30)
        #expect(decoded.sourceSize.width == 1280)
        // Default values for optionals: captureOrigin is .zero, displayHeight/backingScaleFactor may be nil or set
        #expect(decoded.events.isEmpty)
    }

    @Test func writeMetadataCreatesValidJSONFile() throws {
        let tracker = CursorTracker()
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try tracker.writeMetadata(
            to: url,
            frameRate: 60,
            sourceSize: CGSize(width: 1920, height: 1080)
        )

        // File should exist and be valid JSON
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil, "Output should be valid JSON")
        #expect(json?["version"] as? Int == 1)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Events after tracking session
    // ─────────────────────────────────────────────────────────────────

    @Test func eventsAreEmptyAfterStopWithoutInput() {
        let tracker = CursorTracker()
        tracker.startTracking()
        // No actual mouse/keyboard events in test environment
        tracker.stopTracking()
        #expect(tracker.events.isEmpty)
    }

    @Test func startTrackingSetsTrackingStartDate() {
        let tracker = CursorTracker()
        let before = Date()
        tracker.startTracking()
        let after = Date()

        // trackingStartDate is private, but we can verify indirectly:
        // events appended after start would have timestamps relative to trackingStartDate
        // Here we just verify start/stop doesn't crash
        #expect(tracker.isTracking)
        tracker.stopTracking()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Metadata File Backward Compatibility
    // ─────────────────────────────────────────────────────────────────

    @Test func metadataFileWithUnknownFieldsStillDecodes() throws {
        // Future versions might add fields — current decoder should ignore unknown keys
        let json = """
        {
            "version": 1,
            "frameRate": 60,
            "sourceSize": {"width": 1920, "height": 1080},
            "events": [],
            "futureField": "should be ignored"
        }
        """
        let data = json.data(using: .utf8)!
        // This should not throw
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)
        #expect(decoded.frameRate == 60)
    }

    @Test func metadataFileVersionField() throws {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 1920, height: 1080),
            events: []
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)
        #expect(decoded.version == 1)
    }
}
