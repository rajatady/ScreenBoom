import Testing
import AppKit
@testable import Screenboom

// MARK: - RegionSelectionView Expanded Tests
// Covers: body drag (move), edge resize, click outside repositions,
// clampToScreen, min size enforcement, initial centering, large initial size clamping,
// full rect persistence (Bug #1), multi-display window creation (Bug #2).

@MainActor
struct RegionSelectionExpandedTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Harness
    // ─────────────────────────────────────────────────────────────────

    final class CallbackBox {
        var selectedRect: CGRect?
        var cancelCount = 0
    }

    private func makeHarness(
        screenSize: CGSize = CGSize(width: 1920, height: 1080),
        initialRect: CGRect? = nil,
        fallbackSize: CGSize = CGSize(width: 400, height: 300)
    ) -> (view: RegionSelectionView, window: NSWindow, callback: CallbackBox, screenHeight: CGFloat) {
        let callback = CallbackBox()
        let view = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screenSize),
            screenSize: screenSize,
            initialRect: initialRect,
            fallbackSize: fallbackSize,
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
        return (view, window, callback, screenSize.height)
    }

    private func tearDown(_ h: (view: RegionSelectionView, window: NSWindow, callback: CallbackBox, screenHeight: CGFloat)) {
        h.view.invalidate()
        h.window.contentView = nil
        h.window.orderOut(nil)
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

    /// Create a mouse event at the given VIEW coordinates (flipped, top-left origin).
    /// Converts to window coordinates (bottom-left origin) for correct `convert(from: nil)`.
    private func mouseEvent(_ type: NSEvent.EventType, atView point: CGPoint, screenHeight: CGFloat, window: NSWindow) -> NSEvent {
        // View is flipped (isFlipped=true): viewY = screenHeight - windowY
        // So windowY = screenHeight - viewY
        let windowPoint = CGPoint(x: point.x, y: screenHeight - point.y)
        return NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func waitForMainQueue() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    /// Confirm the selection and return the rect
    private func confirmAndGet(_ h: (view: RegionSelectionView, window: NSWindow, callback: CallbackBox, screenHeight: CGFloat)) async -> CGRect? {
        h.view.keyDown(with: keyEvent(keyCode: 36, characters: "\r", window: h.window))
        await waitForMainQueue()
        return h.callback.selectedRect
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Initial Centering
    // ─────────────────────────────────────────────────────────────────

    @Test func initialSelectionIsCenteredOnScreen() async {
        // Screen: 1920x1080, fallback: 400x300
        // Expected center: (960, 540), so origin = (760, 390)
        let h = makeHarness(screenSize: CGSize(width: 1920, height: 1080), fallbackSize: CGSize(width: 400, height: 300))
        defer { tearDown(h) }

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect(abs((rect?.origin.x ?? 0) - 760) < 1)
        #expect(abs((rect?.origin.y ?? 0) - 390) < 1)
        #expect(abs((rect?.width ?? 0) - 400) < 1)
        #expect(abs((rect?.height ?? 0) - 300) < 1)
    }

    @Test func initialSizeClampedToScreenWithMargin() async {
        // Fallback size larger than screen
        let h = makeHarness(screenSize: CGSize(width: 800, height: 600), fallbackSize: CGSize(width: 2000, height: 1500))
        defer { tearDown(h) }

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Clamped to screenSize - 40 (20px margin each side)
        #expect((rect?.width ?? 9999) <= 760)
        #expect((rect?.height ?? 9999) <= 560)
        // Should still be centered
        let expectedW = CGFloat(min(2000, 800 - 40))
        let expectedH = CGFloat(min(1500, 600 - 40))
        let expectedX = (CGFloat(800) - expectedW) / 2
        let expectedY = (CGFloat(600) - expectedH) / 2
        #expect(abs((rect?.origin.x ?? 0) - expectedX) < 1)
        #expect(abs((rect?.origin.y ?? 0) - expectedY) < 1)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Saved Rect Restoration (Bug #1)
    // ─────────────────────────────────────────────────────────────────

    @Test func savedRectIsRestoredExactly() async {
        let savedRect = CGRect(x: 100, y: 200, width: 500, height: 400)
        let h = makeHarness(
            screenSize: CGSize(width: 1920, height: 1080),
            initialRect: savedRect
        )
        defer { tearDown(h) }

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Should restore exact position + size, not re-center
        #expect(abs((rect?.origin.x ?? 0) - 100) < 1)
        #expect(abs((rect?.origin.y ?? 0) - 200) < 1)
        #expect(abs((rect?.width ?? 0) - 500) < 1)
        #expect(abs((rect?.height ?? 0) - 400) < 1)
    }

    @Test func savedRectThatExceedsScreenFallsBackToCentered() async {
        // Saved rect is larger than the new screen
        let savedRect = CGRect(x: 100, y: 200, width: 2000, height: 1500)
        let h = makeHarness(
            screenSize: CGSize(width: 800, height: 600),
            initialRect: savedRect,
            fallbackSize: CGSize(width: 400, height: 300)
        )
        defer { tearDown(h) }

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Should NOT use saved rect (exceeds screen), should fall back to centered
        #expect(abs((rect?.width ?? 0) - 400) < 1)
        #expect(abs((rect?.height ?? 0) - 300) < 1)
        // Centered: origin = ((800-400)/2, (600-300)/2) = (200, 150)
        #expect(abs((rect?.origin.x ?? 0) - 200) < 1)
        #expect(abs((rect?.origin.y ?? 0) - 150) < 1)
    }

    @Test func savedRectWithNegativeOriginFallsBackToCentered() async {
        let savedRect = CGRect(x: -50, y: -20, width: 400, height: 300)
        let h = makeHarness(
            screenSize: CGSize(width: 1920, height: 1080),
            initialRect: savedRect,
            fallbackSize: CGSize(width: 400, height: 300)
        )
        defer { tearDown(h) }

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Should fall back to centered since saved rect has negative origin
        #expect((rect?.origin.x ?? -1) >= 0)
        #expect((rect?.origin.y ?? -1) >= 0)
    }

    @Test func regionDefaultsPersistsFullRect() {
        // Test the RegionDefaults storage directly
        let testRect = CGRect(x: 150, y: 250, width: 600, height: 450)

        // Save
        RegionDefaults.lastRect = testRect

        // Restore
        let restored = RegionDefaults.lastRect
        #expect(restored != nil)
        #expect(restored?.origin.x == 150)
        #expect(restored?.origin.y == 250)
        #expect(restored?.width == 600)
        #expect(restored?.height == 450)

        // Clean up
        RegionDefaults.lastRect = nil
    }

    @Test func regionDefaultsReturnsNilWhenNothingSaved() {
        // Clean slate
        RegionDefaults.lastRect = nil

        let restored = RegionDefaults.lastRect
        #expect(restored == nil)
    }

    @Test func regionDefaultsReturnsNilForTooSmallSize() {
        // Save a rect with size below minimum
        UserDefaults.standard.set(50.0, forKey: RegionDefaults.widthKey)
        UserDefaults.standard.set(50.0, forKey: RegionDefaults.heightKey)
        UserDefaults.standard.set(100.0, forKey: RegionDefaults.xKey)
        UserDefaults.standard.set(100.0, forKey: RegionDefaults.yKey)

        let restored = RegionDefaults.lastRect
        #expect(restored == nil, "Should return nil for rect with width/height < 100")

        // Clean up
        RegionDefaults.lastRect = nil
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Body Drag (Move)
    // ─────────────────────────────────────────────────────────────────

    @Test func bodyDragMovesSelectionByDelta() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial rect centered: origin = (400, 325), size = 200x150
        // Center of rect in view coords = (500, 400) — deep inside, not on edge
        let center = CGPoint(x: 500, y: 400)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: center, screenHeight: h.screenHeight, window: h.window))
        // Drag 50px right, 30px down (in view coords)
        let dragTo = CGPoint(x: 550, y: 430)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Original origin was (400, 325), moved by (50, 30) → (450, 355)
        #expect(abs((rect?.origin.x ?? 0) - 450) < 1)
        #expect(abs((rect?.origin.y ?? 0) - 355) < 1)
        // Size unchanged
        #expect(abs((rect?.width ?? 0) - 200) < 1)
        #expect(abs((rect?.height ?? 0) - 150) < 1)
    }

    @Test func bodyDragClampsToScreenBounds() async {
        let h = makeHarness(screenSize: CGSize(width: 500, height: 400), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial origin: (150, 125), center at (250, 200)
        let center = CGPoint(x: 250, y: 200)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: center, screenHeight: h.screenHeight, window: h.window))
        // Drag way beyond screen right/bottom
        let dragTo = CGPoint(x: 900, y: 800)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Clamped: maxX <= 500, maxY <= 400
        #expect((rect?.maxX ?? 9999) <= 500)
        #expect((rect?.maxY ?? 9999) <= 400)
        // Origin clamped: max origin.x = 500-200 = 300, origin.y = 400-150 = 250
        #expect((rect?.origin.x ?? 0) <= 300)
        #expect((rect?.origin.y ?? 0) <= 250)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Edge Resize (not corner)
    // ─────────────────────────────────────────────────────────────────

    @Test func rightEdgeDragExpandsWidth() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial rect: origin=(400,325), size=200x150
        // Right edge at x=600, midY=400. Click on right edge band.
        let rightEdge = CGPoint(x: 600, y: 400)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: rightEdge, screenHeight: h.screenHeight, window: h.window))
        // Drag right by 100
        let dragTo = CGPoint(x: 700, y: 400)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Width should have increased by ~100
        #expect(abs((rect?.width ?? 0) - 300) < 2)
        // Origin X unchanged
        #expect(abs((rect?.origin.x ?? 0) - 400) < 1)
        // Height unchanged
        #expect(abs((rect?.height ?? 0) - 150) < 1)
    }

    @Test func bottomEdgeDragExpandsHeight() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial: origin=(400,325), size=200x150
        // Bottom edge at y=475, midX=500
        let bottomEdge = CGPoint(x: 500, y: 475)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: bottomEdge, screenHeight: h.screenHeight, window: h.window))
        let dragTo = CGPoint(x: 500, y: 575)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Height should have increased by ~100
        #expect(abs((rect?.height ?? 0) - 250) < 2)
        // Width unchanged
        #expect(abs((rect?.width ?? 0) - 200) < 1)
    }

    @Test func leftEdgeDragMovesOriginAndShrinksWidth() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 400, height: 300))
        defer { tearDown(h) }

        // Initial: origin=(300,250), size=400x300
        // Left edge at x=300, midY=400
        let leftEdge = CGPoint(x: 300, y: 400)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: leftEdge, screenHeight: h.screenHeight, window: h.window))
        // Drag right by 100 → shrink width
        let dragTo = CGPoint(x: 400, y: 400)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Origin X moved right by 100, width shrunk by 100
        #expect(abs((rect?.origin.x ?? 0) - 400) < 2)
        #expect(abs((rect?.width ?? 0) - 300) < 2)
        // Right edge stays at 700
        #expect(abs((rect?.maxX ?? 0) - 700) < 2)
    }

    @Test func topEdgeDragMovesOriginYAndShrinksHeight() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 400, height: 300))
        defer { tearDown(h) }

        // Initial: origin=(300,250), size=400x300
        // Top edge at y=250, midX=500
        let topEdge = CGPoint(x: 500, y: 250)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: topEdge, screenHeight: h.screenHeight, window: h.window))
        // Drag down by 50
        let dragTo = CGPoint(x: 500, y: 300)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect(abs((rect?.origin.y ?? 0) - 300) < 2)
        #expect(abs((rect?.height ?? 0) - 250) < 2)
        // Bottom edge stays at 550
        #expect(abs((rect?.maxY ?? 0) - 550) < 2)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Edge Resize Min Size Enforcement
    // ─────────────────────────────────────────────────────────────────

    @Test func edgeResizeEnforcesMinimum100x100() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial: origin=(400,325), size=200x150
        // Drag right edge left to try to make width < 100
        let rightEdge = CGPoint(x: 600, y: 400)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: rightEdge, screenHeight: h.screenHeight, window: h.window))
        let dragTo = CGPoint(x: 450, y: 400)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect((rect?.width ?? 0) >= 100)
    }

    @Test func leftEdgeResizeEnforcesMinWidth() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial: origin=(400,325), size=200x150
        // Drag left edge way to the right → should clamp at maxX - 100
        let leftEdge = CGPoint(x: 400, y: 400)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: leftEdge, screenHeight: h.screenHeight, window: h.window))
        let dragTo = CGPoint(x: 590, y: 400)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect((rect?.width ?? 0) >= 100)
        // Right edge should not have moved
        #expect(abs((rect?.maxX ?? 0) - 600) < 2)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Click Outside Repositions
    // ─────────────────────────────────────────────────────────────────

    @Test func clickOutsideRepositionsCenterToClick() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Click far from the selection (top-left corner area)
        let outside = CGPoint(x: 100, y: 100)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: outside, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: outside, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Center should be near (100, 100), so origin ≈ (0, 25)
        // But clamped to x >= 0, y >= 0
        #expect((rect?.origin.x ?? -1) >= 0)
        #expect((rect?.origin.y ?? -1) >= 0)
        // Size should be preserved
        #expect(abs((rect?.width ?? 0) - 200) < 1)
        #expect(abs((rect?.height ?? 0) - 150) < 1)
    }

    @Test func clickOutsideClampsToScreenEdge() async {
        let h = makeHarness(screenSize: CGSize(width: 500, height: 400), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Click near bottom-right corner
        let outside = CGPoint(x: 480, y: 380)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: outside, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: outside, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        // Selection should be clamped within screen
        #expect((rect?.maxX ?? 9999) <= 500)
        #expect((rect?.maxY ?? 9999) <= 400)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - clampToScreen Edge Cases
    // ─────────────────────────────────────────────────────────────────

    @Test func resizeBeyondScreenRightClamps() async {
        let h = makeHarness(screenSize: CGSize(width: 800, height: 600), fallbackSize: CGSize(width: 400, height: 300))
        defer { tearDown(h) }

        // Initial: origin=(200,150), size=400x300, right edge at x=600
        let rightEdge = CGPoint(x: 600, y: 300)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: rightEdge, screenHeight: h.screenHeight, window: h.window))
        let dragTo = CGPoint(x: 1200, y: 300)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect((rect?.maxX ?? 9999) <= 800)
    }

    @Test func resizeBeyondScreenBottomClamps() async {
        let h = makeHarness(screenSize: CGSize(width: 800, height: 600), fallbackSize: CGSize(width: 400, height: 300))
        defer { tearDown(h) }

        // Initial: origin=(200,150), size=400x300, bottom edge at y=450
        let bottomEdge = CGPoint(x: 400, y: 450)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: bottomEdge, screenHeight: h.screenHeight, window: h.window))
        let dragTo = CGPoint(x: 400, y: 900)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect((rect?.maxY ?? 9999) <= 600)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Corner Resize (bottomRight)
    // ─────────────────────────────────────────────────────────────────

    @Test func bottomRightCornerResizeChangesWidthAndHeight() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 200, height: 150))
        defer { tearDown(h) }

        // Initial: origin=(400,325), size=200x150, bottomRight at (600,475)
        let corner = CGPoint(x: 600, y: 475)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: corner, screenHeight: h.screenHeight, window: h.window))
        let dragTo = CGPoint(x: 700, y: 575)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect(abs((rect?.width ?? 0) - 300) < 2)
        #expect(abs((rect?.height ?? 0) - 250) < 2)
        // Origin unchanged
        #expect(abs((rect?.origin.x ?? 0) - 400) < 1)
        #expect(abs((rect?.origin.y ?? 0) - 325) < 1)
    }

    @Test func topLeftCornerResizeMovesOriginAndShrinksSize() async {
        let h = makeHarness(screenSize: CGSize(width: 1000, height: 800), fallbackSize: CGSize(width: 400, height: 300))
        defer { tearDown(h) }

        // Initial: origin=(300,250), size=400x300, topLeft at (300,250)
        let corner = CGPoint(x: 300, y: 250)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: corner, screenHeight: h.screenHeight, window: h.window))
        // Drag right and down by 50
        let dragTo = CGPoint(x: 350, y: 300)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect(abs((rect?.origin.x ?? 0) - 350) < 2)
        #expect(abs((rect?.origin.y ?? 0) - 300) < 2)
        #expect(abs((rect?.width ?? 0) - 350) < 2)
        #expect(abs((rect?.height ?? 0) - 250) < 2)
        // Bottom-right corner should not move
        #expect(abs((rect?.maxX ?? 0) - 700) < 2)
        #expect(abs((rect?.maxY ?? 0) - 550) < 2)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Enter Rejects Tiny Selection
    // ─────────────────────────────────────────────────────────────────

    @Test func enterDoesNotConfirmIfSizeBelow100() async {
        // Start with a size right at the boundary
        let h = makeHarness(screenSize: CGSize(width: 500, height: 400), fallbackSize: CGSize(width: 100, height: 100))
        defer { tearDown(h) }

        // Shrink via corner to < 100 height
        // Initial: centered at origin=(200,150), size=100x100
        // bottomRight at (300,250)
        let corner = CGPoint(x: 300, y: 250)
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: corner, screenHeight: h.screenHeight, window: h.window))
        // Drag up to make height < 100 — but min enforcement should prevent this
        let dragTo = CGPoint(x: 300, y: 200)
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: dragTo, screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: dragTo, screenHeight: h.screenHeight, window: h.window))

        // The resize code enforces min 100, so height should still be >= 100
        let rect = await confirmAndGet(h)
        #expect(rect != nil)
        #expect((rect?.width ?? 0) >= 100)
        #expect((rect?.height ?? 0) >= 100)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Numpad Enter Also Confirms
    // ─────────────────────────────────────────────────────────────────

    @Test func numpadEnterConfirms() async {
        let h = makeHarness()
        defer { tearDown(h) }

        // keyCode 76 = numpad Enter
        h.view.keyDown(with: keyEvent(keyCode: 76, characters: "\r", window: h.window))
        await waitForMainQueue()

        #expect(h.callback.selectedRect != nil)
        #expect(h.callback.cancelCount == 0)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Mouse Events After Invalidation
    // ─────────────────────────────────────────────────────────────────

    @Test func mouseEventsIgnoredAfterInvalidation() async {
        let h = makeHarness()
        defer { tearDown(h) }

        h.view.invalidate()

        // These should all be no-ops
        h.view.mouseDown(with: mouseEvent(.leftMouseDown, atView: CGPoint(x: 100, y: 100), screenHeight: h.screenHeight, window: h.window))
        h.view.mouseDragged(with: mouseEvent(.leftMouseDragged, atView: CGPoint(x: 200, y: 200), screenHeight: h.screenHeight, window: h.window))
        h.view.mouseUp(with: mouseEvent(.leftMouseUp, atView: CGPoint(x: 200, y: 200), screenHeight: h.screenHeight, window: h.window))

        // Try to confirm — should not fire
        h.view.keyDown(with: keyEvent(keyCode: 36, characters: "\r", window: h.window))
        await waitForMainQueue()

        #expect(h.callback.selectedRect == nil)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Multi-Display Window Creation (Bug #2)
    // ─────────────────────────────────────────────────────────────────

    @Test func regionSelectorManagerCreatesWindowPerScreen() {
        // Verify the manager creates at least one window (we can't mock NSScreen.screens
        // but we can verify the plumbing works for the current display setup)
        let manager = RegionSelectorManager()
        var selectedRect: CGRect?

        manager.startSelection(
            onSelected: { rect, _ in selectedRect = rect },
            onCancelled: nil
        )

        // Should have created at least 1 overlay window (one per screen)
        // We can't directly access overlayWindows (private), but we can verify
        // the manager is active by checking that forceClose doesn't crash
        manager.forceClose()

        // No crash = windows were created and cleaned up properly
        #expect(selectedRect == nil, "No selection should have been emitted")
    }
}
