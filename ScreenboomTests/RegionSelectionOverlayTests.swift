import Testing
import AppKit
@testable import Screenboom

@MainActor
struct RegionSelectionOverlayTests {
    final class CallbackBox {
        var selectedRect: CGRect?
        var cancelCount = 0
    }

    private func waitForMainQueue() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    private func makeHarness(
        screenSize: CGSize = CGSize(width: 800, height: 600),
        initialSize: CGSize = CGSize(width: 200, height: 120)
    ) -> (view: RegionSelectionView, window: NSWindow, callback: CallbackBox) {
        let callback = CallbackBox()
        let view = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screenSize),
            screenSize: screenSize,
            initialSize: initialSize,
            onSelected: { rect in callback.selectedRect = rect },
            onCancelled: { callback.cancelCount += 1 }
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: screenSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view
        window.contentView?.layoutSubtreeIfNeeded()
        return (view, window, callback)
    }

    private func tearDownHarness(_ harness: (view: RegionSelectionView, window: NSWindow, callback: CallbackBox)) {
        harness.view.invalidate()
        harness.window.contentView = nil
        harness.window.orderOut(nil)
    }

    private func keyEvent(keyCode: UInt16, characters: String, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func mouseEvent(type: NSEvent.EventType, viewPoint: CGPoint, window: NSWindow) -> NSEvent {
        return NSEvent.mouseEvent(
            with: type,
            location: viewPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    @Test func enterConfirmsCurrentSelectionRect() async {
        let harness = makeHarness()
        defer { tearDownHarness(harness) }

        harness.view.keyDown(with: keyEvent(keyCode: 36, characters: "\r", window: harness.window))
        await waitForMainQueue()

        #expect(harness.callback.cancelCount == 0)
        #expect(harness.callback.selectedRect != nil)
        #expect(abs((harness.callback.selectedRect?.width ?? 0) - 200) < 0.0001)
        #expect(abs((harness.callback.selectedRect?.height ?? 0) - 120) < 0.0001)
    }

    @Test func escapeCancelsSelection() async {
        let harness = makeHarness()
        defer { tearDownHarness(harness) }

        harness.view.keyDown(with: keyEvent(keyCode: 53, characters: "\u{1B}", window: harness.window))
        await waitForMainQueue()

        #expect(harness.callback.selectedRect == nil)
        #expect(harness.callback.cancelCount == 1)
    }

    @Test func resizeViaCornerEnforcesMinimumSizeAndClampsToBounds() async {
        let harness = makeHarness(screenSize: CGSize(width: 800, height: 600), initialSize: CGSize(width: 200, height: 120))
        defer { tearDownHarness(harness) }

        // Default centered rect for this harness is x:300 y:240 width:200 height:120 (view coordinates).
        harness.view.mouseDown(with: mouseEvent(type: .leftMouseDown, viewPoint: CGPoint(x: 300, y: 240), window: harness.window))
        harness.view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, viewPoint: CGPoint(x: 480, y: 360), window: harness.window))
        harness.view.mouseUp(with: mouseEvent(type: .leftMouseUp, viewPoint: CGPoint(x: 480, y: 360), window: harness.window))

        harness.view.keyDown(with: keyEvent(keyCode: 36, characters: "\r", window: harness.window))
        await waitForMainQueue()

        let rect = harness.callback.selectedRect
        #expect(rect != nil)
        #expect((rect?.width ?? 0) >= 100)
        #expect((rect?.height ?? 0) >= 100)
        #expect((rect?.minX ?? -1) >= 0)
        #expect((rect?.minY ?? -1) >= 0)
        #expect((rect?.maxX ?? 9999) <= 800)
        #expect((rect?.maxY ?? 9999) <= 600)
    }

    @Test func invalidateSuppressesCallbacks() async {
        let harness = makeHarness()
        defer { tearDownHarness(harness) }
        harness.view.invalidate()

        harness.view.keyDown(with: keyEvent(keyCode: 36, characters: "\r", window: harness.window))
        harness.view.keyDown(with: keyEvent(keyCode: 53, characters: "\u{1B}", window: harness.window))
        await waitForMainQueue()

        #expect(harness.callback.selectedRect == nil)
        #expect(harness.callback.cancelCount == 0)
    }
}
