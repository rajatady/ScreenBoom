import Foundation

// MARK: - Cursor Event

struct CursorEvent: Codable, Sendable {
    enum EventType: String, Codable, Sendable {
        case move
        case click
        case release
        case scroll
        case keyDown
    }

    enum Button: String, Codable, Sendable {
        case left
        case right
    }

    var timestamp: Double
    var x: Double
    var y: Double
    var type: EventType
    var button: Button?
}

// MARK: - Cursor Metadata File

struct CursorMetadataFile: Codable, Sendable {
    var version: Int = 1
    var frameRate: Double
    var sourceSize: CodableSize
    var captureOrigin: CodablePoint?  // screen origin of capture area (Quartz coords, optional for backward compat)
    var displayHeight: Double?        // primary screen height in points (for Cocoa→Quartz Y conversion)
    var backingScaleFactor: Double?   // Retina scale factor (1.0 or 2.0)
    var events: [CursorEvent]

    struct CodableSize: Codable, Sendable {
        var width: Double
        var height: Double
    }

    struct CodablePoint: Codable, Sendable {
        var x: Double
        var y: Double
    }
}

// MARK: - Recording Session

struct RecordingSession: Sendable {
    var videoURL: URL
    var cursorMetadataURL: URL?
    var duration: Double
    var sourceSize: CGSize
    var frameRate: Double
    var displayName: String
    var startDate: Date
}
