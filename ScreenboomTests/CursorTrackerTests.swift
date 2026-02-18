import Testing
import Foundation
@testable import Screenboom

@MainActor
struct CursorTrackerTests {
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-metadata-\(UUID().uuidString).json")
    }

    @Test func writeMetadataPersistsCaptureGeometryAndFrameInfo() throws {
        let tracker = CursorTracker()
        tracker.captureOrigin = CGPoint(x: 123, y: 456)
        tracker.displayHeight = 900
        tracker.backingScaleFactor = 2.0
        let outputURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try tracker.writeMetadata(
            to: outputURL,
            frameRate: 60,
            sourceSize: CGSize(width: 1920, height: 1080)
        )

        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(CursorMetadataFile.self, from: data)

        #expect(decoded.frameRate == 60)
        #expect(decoded.sourceSize.width == 1920)
        #expect(decoded.sourceSize.height == 1080)
        #expect(decoded.captureOrigin?.x == 123)
        #expect(decoded.captureOrigin?.y == 456)
        #expect(decoded.displayHeight == 900)
        #expect(decoded.backingScaleFactor == 2.0)
        #expect(decoded.events.isEmpty)
    }

    @Test func stopTrackingIsSafeWhenTrackerIsIdle() {
        let tracker = CursorTracker()
        #expect(!tracker.isTracking)

        tracker.stopTracking()

        #expect(!tracker.isTracking)
        #expect(tracker.events.isEmpty)
    }
}
