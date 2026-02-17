import Foundation

// MARK: - Cursor Event

struct CursorEvent: Codable, Sendable {
    enum EventType: String, Codable, Sendable {
        case move
        case click
        case release
        case scroll
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
    var events: [CursorEvent]

    struct CodableSize: Codable, Sendable {
        var width: Double
        var height: Double
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
