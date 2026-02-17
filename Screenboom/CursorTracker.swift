import Foundation
import AppKit

@Observable
final class CursorTracker {
    private(set) var events: [CursorEvent] = []
    private(set) var isTracking = false

    /// Screen origin of the capture area (set before startTracking)
    var captureOrigin: CGPoint = .zero

    private var moveMonitor: Any?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var lastMoveTimestamp: TimeInterval = 0
    private var lastKeyTimestamp: TimeInterval = 0
    private var trackingStartDate: Date?

    // 120Hz move sampling — minimum 1/120s between move events
    private let moveInterval: TimeInterval = 1.0 / 120.0
    // 4Hz key sampling — we only need activity regions, not every keystroke
    private let keyInterval: TimeInterval = 1.0 / 4.0

    func startTracking() {
        guard !isTracking else { return }
        events.removeAll()
        trackingStartDate = Date()
        isTracking = true

        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMove(event)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { [weak self] event in
            self?.handleClick(event)
        }

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false

        if let m = moveMonitor { NSEvent.removeMonitor(m) }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        moveMonitor = nil
        clickMonitor = nil
        scrollMonitor = nil
        keyMonitor = nil
    }

    func writeMetadata(to url: URL, frameRate: Double, sourceSize: CGSize) throws {
        let metadata = CursorMetadataFile(
            frameRate: frameRate,
            sourceSize: CursorMetadataFile.CodableSize(
                width: Double(sourceSize.width),
                height: Double(sourceSize.height)
            ),
            captureOrigin: CursorMetadataFile.CodablePoint(
                x: Double(captureOrigin.x),
                y: Double(captureOrigin.y)
            ),
            events: events
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Event Handlers

    private func handleMove(_ event: NSEvent) {
        let now = event.timestamp
        guard now - lastMoveTimestamp >= moveInterval else { return }
        lastMoveTimestamp = now

        let location = NSEvent.mouseLocation
        appendEvent(type: .move, location: location, button: nil)
    }

    private func handleClick(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let isLeft = event.type == .leftMouseDown || event.type == .leftMouseUp
        let button: CursorEvent.Button = isLeft ? .left : .right
        let type: CursorEvent.EventType = (event.type == .leftMouseDown || event.type == .rightMouseDown) ? .click : .release
        appendEvent(type: type, location: location, button: button)
    }

    private func handleScroll(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        appendEvent(type: .scroll, location: location, button: nil)
    }

    private func handleKeyDown(_ event: NSEvent) {
        let now = event.timestamp
        guard now - lastKeyTimestamp >= keyInterval else { return }
        lastKeyTimestamp = now

        // Record at current cursor position — we care about WHERE typing happens, not WHAT
        let location = NSEvent.mouseLocation
        appendEvent(type: .keyDown, location: location, button: nil)
    }

    private func appendEvent(type: CursorEvent.EventType, location: NSPoint, button: CursorEvent.Button?) {
        guard let start = trackingStartDate else { return }
        let timestamp = Date().timeIntervalSince(start)
        events.append(CursorEvent(
            timestamp: timestamp,
            x: Double(location.x),
            y: Double(location.y), // NSEvent uses bottom-left origin — stored as-is, converted at render time
            type: type,
            button: button
        ))
    }
}
