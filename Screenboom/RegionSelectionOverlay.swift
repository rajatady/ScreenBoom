import AppKit
import SwiftUI
import os

private let regionLog = Logger(subsystem: "com.trymagically.Screenboom", category: "RegionSelect")

// MARK: - Persisted Region Rect

enum RegionDefaults {
    static let widthKey = "RegionSelection.lastWidth"
    static let heightKey = "RegionSelection.lastHeight"
    static let xKey = "RegionSelection.lastX"
    static let yKey = "RegionSelection.lastY"
    /// Tracks which screen the rect was saved on (by screen.frame description)
    static let screenKey = "RegionSelection.lastScreenFrame"

    static let defaultSize = CGSize(width: 1280, height: 720)

    /// Full rect (position + size) persisted from last session.
    /// Returns nil if no valid rect was previously saved.
    static var lastRect: CGRect? {
        get {
            let w = UserDefaults.standard.double(forKey: widthKey)
            let h = UserDefaults.standard.double(forKey: heightKey)
            guard w >= 100, h >= 100 else { return nil }
            let x = UserDefaults.standard.double(forKey: xKey)
            let y = UserDefaults.standard.double(forKey: yKey)
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            if let rect = newValue {
                UserDefaults.standard.set(rect.origin.x, forKey: xKey)
                UserDefaults.standard.set(rect.origin.y, forKey: yKey)
                UserDefaults.standard.set(rect.size.width, forKey: widthKey)
                UserDefaults.standard.set(rect.size.height, forKey: heightKey)
            } else {
                UserDefaults.standard.removeObject(forKey: xKey)
                UserDefaults.standard.removeObject(forKey: yKey)
                UserDefaults.standard.removeObject(forKey: widthKey)
                UserDefaults.standard.removeObject(forKey: heightKey)
            }
        }
    }

    /// The size to use when no saved rect exists, or as a fallback.
    static var lastSize: CGSize {
        lastRect?.size ?? defaultSize
    }

    static var lastScreenFrame: String? {
        get { UserDefaults.standard.string(forKey: screenKey) }
        set { UserDefaults.standard.set(newValue, forKey: screenKey) }
    }
}

// MARK: - Region Selector Manager

@Observable
final class RegionSelectorManager {
    private var overlayWindows: [RegionSelectionWindow] = []
    private var onRegionSelected: ((CGRect, NSScreen) -> Void)?
    private var onCancelledCallback: (() -> Void)?

    /// Show region selection overlay on all screens.
    /// - Parameters:
    ///   - onSelected: Called with the screen-coordinate rect and the screen it was drawn on.
    ///   - onCancelled: Called when the user cancels (Escape) or selection is programmatically dismissed.
    func startSelection(onSelected: @escaping (CGRect, NSScreen) -> Void, onCancelled: (() -> Void)? = nil) {
        forceClose()
        onRegionSelected = onSelected
        onCancelledCallback = onCancelled

        let savedRect = RegionDefaults.lastRect

        for screen in NSScreen.screens {
            let window = RegionSelectionWindow(
                screen: screen,
                initialRect: savedRect,
                fallbackSize: RegionDefaults.defaultSize,
                onSelected: { [weak self] rect in
                    self?.handleSelection(rect, from: screen)
                },
                onCancelled: { [weak self] in
                    guard let self, !self.overlayWindows.isEmpty else { return }
                    let cb = self.onCancelledCallback
                    self.onRegionSelected = nil
                    self.onCancelledCallback = nil
                    self.teardownWindows()
                    cb?()
                }
            )
            overlayWindows.append(window)
        }

        // Order all windows front (orderFrontRegardless ensures visibility
        // even on non-primary screens), then make the mouse-screen window key.
        let mouseLocation = NSEvent.mouseLocation
        var keyWindow: RegionSelectionWindow?
        for (i, window) in overlayWindows.enumerated() {
            window.orderFrontRegardless()
            if NSScreen.screens.indices.contains(i) {
                let screen = NSScreen.screens[i]
                if screen.frame.contains(mouseLocation) {
                    keyWindow = window
                }
            }
        }
        (keyWindow ?? overlayWindows.first)?.makeKey()
    }

    /// Programmatically cancel the selection. Fires the onCancelled callback.
    func cancelSelection() {
        guard !overlayWindows.isEmpty else { return }
        let cb = onCancelledCallback
        onRegionSelected = nil
        onCancelledCallback = nil
        teardownWindows()
        cb?()
    }

    /// Close all overlays without firing any callbacks. Used during teardown.
    func forceClose() {
        onRegionSelected = nil
        onCancelledCallback = nil
        teardownWindows()
    }

    // MARK: - Private

    private func teardownWindows() {
        let windows = overlayWindows
        overlayWindows.removeAll()

        for window in windows {
            (window.contentView as? RegionSelectionView)?.invalidate()
            window.ignoresMouseEvents = true
            window.close()
        }
    }

    private func handleSelection(_ viewRect: CGRect, from screen: NSScreen) {
        // viewRect is display-relative top-left coords (view is flipped).
        // SCStreamConfiguration.sourceRect uses the SAME coordinate system
        // (display coordinates, top-left origin). Pass viewRect directly — no Y-flip.
        RegionDefaults.lastRect = viewRect
        RegionDefaults.lastScreenFrame = screen.frame.debugDescription

        regionLog.info("""
        [REGION] handleSelection:
          viewRect=\(viewRect.debugDescription)
          screen.frame=\(screen.frame.debugDescription)
          screen.backingScaleFactor=\(screen.backingScaleFactor)
          (passing viewRect directly — display-relative top-left for SCK)
        """)

        let callback = onRegionSelected
        onRegionSelected = nil
        onCancelledCallback = nil
        teardownWindows()
        callback?(viewRect, screen)
    }
}

// MARK: - Region Selection Window

final class RegionSelectionWindow: NSWindow {

    init(screen: NSScreen, initialRect: CGRect?, fallbackSize: CGSize, onSelected: @escaping (CGRect) -> Void, onCancelled: @escaping () -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        acceptsMouseMovedEvents = true

        let selectionView = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenSize: screen.frame.size,
            initialRect: initialRect,
            fallbackSize: fallbackSize,
            onSelected: onSelected,
            onCancelled: onCancelled
        )
        contentView = selectionView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Drag Handle

private enum DragHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right

    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        }
    }
}

// MARK: - Region Selection View

final class RegionSelectionView: NSView {
    private var selectionRect: CGRect
    private let screenSize: CGSize
    private var onSelected: ((CGRect) -> Void)?
    private var onCancelled: (() -> Void)?

    private var isInvalidated = false

    // Drag state
    private var activeHandle: DragHandle?
    private var isDraggingBody = false
    private var dragStartPoint: NSPoint = .zero
    private var dragStartRect: CGRect = .zero

    // Visual constants
    private let handleSize: CGFloat = 10
    private let edgeBand: CGFloat = 16
    private let overlayColor = NSColor.black.withAlphaComponent(0.4) // sb-exempt — CGContext drawing
    private let accentColor = SB.Colors.accentNS
    private let accentFillColor = SB.Colors.accentNS.withAlphaComponent(0.05)
    private let dimensionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private let hintFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let labelBgColor = NSColor.black.withAlphaComponent(0.75) // sb-exempt — CGContext drawing

    init(frame: NSRect, screenSize: CGSize, initialRect: CGRect?, fallbackSize: CGSize, onSelected: @escaping (CGRect) -> Void, onCancelled: @escaping () -> Void) {
        if let saved = initialRect,
           saved.width >= 100, saved.height >= 100,
           saved.maxX <= screenSize.width, saved.maxY <= screenSize.height,
           saved.origin.x >= 0, saved.origin.y >= 0 {
            // Restore exact saved position + size
            self.selectionRect = saved
        } else {
            // No saved rect, or it doesn't fit this screen — center with fallback size
            let w = min(fallbackSize.width, screenSize.width - 40)
            let h = min(fallbackSize.height, screenSize.height - 40)
            self.selectionRect = CGRect(
                x: (screenSize.width - w) / 2,
                y: (screenSize.height - h) / 2,
                width: w,
                height: h
            )
        }
        self.screenSize = screenSize
        self.onSelected = onSelected
        self.onCancelled = onCancelled
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func invalidate() {
        isInvalidated = true
        onSelected = nil
        onCancelled = nil
    }

    override var acceptsFirstResponder: Bool { !isInvalidated }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !isInvalidated {
            window?.makeFirstResponder(self)
        }
    }

    // MARK: - Edge-Band Hit Testing

    /// Detects which resize handle (or edge) the point is near.
    /// Uses full edge bands instead of point-based midpoint hit zones,
    /// so the ENTIRE bottom/top/left/right edge is a resize zone.
    /// Returns nil only when the point is deep inside (move zone) or far outside.
    private func handleAt(_ point: NSPoint) -> DragHandle? {
        let r = selectionRect

        // Point must be within the expanded rect (edge band extends outside too)
        let expanded = r.insetBy(dx: -edgeBand, dy: -edgeBand)
        guard expanded.contains(point) else { return nil }

        let nearLeft   = abs(point.x - r.minX) < edgeBand
        let nearRight  = abs(point.x - r.maxX) < edgeBand
        let nearTop    = abs(point.y - r.minY) < edgeBand
        let nearBottom = abs(point.y - r.maxY) < edgeBand

        // Corners: intersection of two edge bands
        if nearTop && nearLeft     { return .topLeft }
        if nearTop && nearRight    { return .topRight }
        if nearBottom && nearLeft  { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }

        // Full edges
        if nearTop    { return .top }
        if nearBottom { return .bottom }
        if nearLeft   { return .left }
        if nearRight  { return .right }

        return nil // deep inside — body move zone
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard !isInvalidated else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragStartPoint = point
        dragStartRect = selectionRect

        if let handle = handleAt(point) {
            // Edge or corner — resize
            activeHandle = handle
        } else if selectionRect.contains(point) {
            // Deep inside — move
            isDraggingBody = true
        } else {
            // Outside selection — reposition center to click
            let w = selectionRect.width
            let h = selectionRect.height
            selectionRect = CGRect(
                x: max(0, min(point.x - w / 2, screenSize.width - w)),
                y: max(0, min(point.y - h / 2, screenSize.height - h)),
                width: w, height: h
            )
            isDraggingBody = true
            dragStartPoint = point
            dragStartRect = selectionRect
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isInvalidated else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragStartPoint.x
        let dy = point.y - dragStartPoint.y
        let orig = dragStartRect
        let minSize: CGFloat = 100

        if let handle = activeHandle {
            var newRect = orig
            switch handle {
            case .topLeft:
                newRect.origin.x = min(orig.origin.x + dx, orig.maxX - minSize)
                newRect.origin.y = min(orig.origin.y + dy, orig.maxY - minSize)
                newRect.size.width = orig.maxX - newRect.origin.x
                newRect.size.height = orig.maxY - newRect.origin.y
            case .topRight:
                newRect.origin.y = min(orig.origin.y + dy, orig.maxY - minSize)
                newRect.size.width = max(minSize, orig.width + dx)
                newRect.size.height = orig.maxY - newRect.origin.y
            case .bottomLeft:
                newRect.origin.x = min(orig.origin.x + dx, orig.maxX - minSize)
                newRect.size.width = orig.maxX - newRect.origin.x
                newRect.size.height = max(minSize, orig.height + dy)
            case .bottomRight:
                newRect.size.width = max(minSize, orig.width + dx)
                newRect.size.height = max(minSize, orig.height + dy)
            case .top:
                newRect.origin.y = min(orig.origin.y + dy, orig.maxY - minSize)
                newRect.size.height = orig.maxY - newRect.origin.y
            case .bottom:
                newRect.size.height = max(minSize, orig.height + dy)
            case .left:
                newRect.origin.x = min(orig.origin.x + dx, orig.maxX - minSize)
                newRect.size.width = orig.maxX - newRect.origin.x
            case .right:
                newRect.size.width = max(minSize, orig.width + dx)
            }
            newRect = clampToScreen(newRect)
            selectionRect = newRect
        } else if isDraggingBody {
            var newRect = orig.offsetBy(dx: dx, dy: dy)
            newRect.origin.x = max(0, min(newRect.origin.x, screenSize.width - newRect.width))
            newRect.origin.y = max(0, min(newRect.origin.y, screenSize.height - newRect.height))
            selectionRect = newRect
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !isInvalidated else { return }
        activeHandle = nil
        isDraggingBody = false
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isInvalidated, window != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let handle = handleAt(point) {
            handle.cursor.set()
        } else if selectionRect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !isInvalidated else { return }
        switch event.keyCode {
        case 53: // Escape
            isInvalidated = true
            let cb = onCancelled
            onSelected = nil
            onCancelled = nil
            DispatchQueue.main.async { cb?() }
        case 36, 76: // Enter / numpad Enter
            if selectionRect.width >= 100 && selectionRect.height >= 100 {
                isInvalidated = true
                let cb = onSelected
                let rect = selectionRect
                onSelected = nil
                onCancelled = nil
                DispatchQueue.main.async { cb?(rect) }
            }
        default:
            break
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !isInvalidated else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let r = selectionRect

        // Dim overlay with punched-out selection
        ctx.setFillColor(overlayColor.cgColor)
        ctx.addRect(bounds)
        ctx.addRect(r)
        ctx.fillPath(using: .evenOdd)

        // Light accent fill inside selection
        ctx.setFillColor(accentFillColor.cgColor)
        ctx.fill(r)

        // Selection border
        ctx.setStrokeColor(accentColor.cgColor)
        ctx.setLineWidth(2.0)
        ctx.stroke(r)

        // Grid lines (rule of thirds)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.1).cgColor)
        ctx.setLineWidth(0.5)
        let thirdW = r.width / 3
        let thirdH = r.height / 3
        for i in 1...2 {
            let x = r.origin.x + thirdW * CGFloat(i)
            ctx.move(to: CGPoint(x: x, y: r.minY))
            ctx.addLine(to: CGPoint(x: x, y: r.maxY))
            let y = r.origin.y + thirdH * CGFloat(i)
            ctx.move(to: CGPoint(x: r.minX, y: y))
            ctx.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.strokePath()

        drawHandles(in: ctx)

        let dimText = "\(Int(r.width)) \u{00D7} \(Int(r.height))"
        drawLabel(dimText, centerX: r.midX, y: r.maxY + 12, in: ctx)

        let hint = "Drag edges to resize  \u{00B7}  Enter to confirm  \u{00B7}  Esc to cancel"
        drawLabel(hint, centerX: bounds.midX, y: 20, in: ctx, font: hintFont)
    }

    private func drawHandles(in ctx: CGContext) {
        let r = selectionRect
        let hs = handleSize

        // Corner handles (accent color, larger)
        let corners: [(CGFloat, CGFloat)] = [
            (r.minX, r.minY), (r.maxX, r.minY),
            (r.minX, r.maxY), (r.maxX, r.maxY)
        ]

        // Edge midpoint handles (white, smaller — visual cues for full-edge resize)
        let edges: [(CGFloat, CGFloat)] = [
            (r.midX, r.minY), (r.midX, r.maxY),
            (r.minX, r.midY), (r.maxX, r.midY)
        ]

        ctx.setFillColor(accentColor.cgColor)
        for (cx, cy) in corners {
            let rect = CGRect(x: cx - hs / 2, y: cy - hs / 2, width: hs, height: hs)
            ctx.fill(rect)
        }

        let es = hs * 0.7
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        for (cx, cy) in edges {
            let rect = CGRect(x: cx - es / 2, y: cy - es / 2, width: es, height: es)
            ctx.fill(rect)
        }
    }

    private func drawLabel(_ text: String, centerX: CGFloat, y: CGFloat, in ctx: CGContext, font: NSFont? = nil) {
        let usedFont = font ?? dimensionFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: usedFont,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 8
        let bgW = size.width + pad * 2
        let bgH = size.height + pad

        let bgRect = CGRect(x: centerX - bgW / 2, y: y, width: bgW, height: bgH)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: bgH / 2, yRadius: bgH / 2)
        ctx.saveGState()
        labelBgColor.setFill()
        path.fill()
        ctx.restoreGState()

        str.draw(at: NSPoint(x: bgRect.minX + pad, y: bgRect.minY + (bgH - size.height) / 2))
    }

#if DEBUG
    /// Expose internal selection rect for test diagnostics
    var _selectionRectForTesting: CGRect { selectionRect }
#endif

    private func clampToScreen(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = max(0, r.origin.x)
        r.origin.y = max(0, r.origin.y)
        if r.maxX > screenSize.width { r.size.width = screenSize.width - r.origin.x }
        if r.maxY > screenSize.height { r.size.height = screenSize.height - r.origin.y }
        return r
    }
}
