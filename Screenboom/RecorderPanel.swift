import SwiftUI
import AppKit

// MARK: - Floating Panel (NSPanel subclass)

/// Always-on-top, non-activating, invisible to ScreenCaptureKit.
/// Accepts clicks without stealing focus from the recorded app.
final class RecorderFloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false      // CRITICAL: prevents double-free with ARC
        level = .floating
        sharingType = .none               // invisible to screen recording
        hidesOnDeactivate = false          // stays visible when switching apps
        isMovableByWindowBackground = true // draggable by clicking anywhere
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                  // SwiftUI provides its own shadow
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Panel Manager

/// Lifecycle manager for the recorder floating panel.
/// Creates a RecorderFlowController internally — callers just provide the completion handler.
/// Injected into SwiftUI environment so WelcomeView (and others) can trigger it.
@Observable
final class RecorderPanelManager {
    private(set) var isShowing = false
    private var panel: RecorderFloatingPanel?
    private var flowController: RecorderFlowController?

    /// Show the recorder bar.
    /// - Parameter onComplete: Called with the RecordingSession when recording finishes.
    func show(onComplete: @escaping (RecordingSession) -> Void) {
        guard !isShowing else { return }

        let flow = RecorderFlowController()
        flowController = flow

        let barView = RecorderBarView(
            flow: flow,
            onComplete: { [weak self] session in
                self?.dismiss()
                onComplete(session)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: barView)
        hostingView.sizingOptions = [.intrinsicContentSize]

        let fittingSize = hostingView.fittingSize
        let initialRect = NSRect(x: 0, y: 0, width: max(fittingSize.width, 320), height: max(fittingSize.height, 48))

        let floatingPanel = RecorderFloatingPanel(contentRect: initialRect)
        floatingPanel.contentView = hostingView

        // Position center-top of main screen, 60pt from top
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - initialRect.width / 2
            let y = screenFrame.maxY - initialRect.height - 60
            floatingPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        floatingPanel.orderFrontRegardless()
        panel = floatingPanel
        isShowing = true

        if let hostingView = floatingPanel.contentView as? NSHostingView<RecorderBarView> {
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            startResizeObserver()
        }
    }

    func dismiss() {
        resizeTimer?.invalidate()
        resizeTimer = nil
        flowController?.teardown()
        panel?.close()
        panel = nil
        flowController = nil
        isShowing = false
    }

    // MARK: - Auto-resize

    private var resizeTimer: Timer?

    private func startResizeObserver() {
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePanelSize()
        }
    }

    private func updatePanelSize() {
        guard let panel, let hostingView = panel.contentView else { return }
        let fitting = hostingView.fittingSize
        let currentSize = panel.frame.size
        let tolerance: CGFloat = 1.0

        if abs(fitting.width - currentSize.width) > tolerance || abs(fitting.height - currentSize.height) > tolerance {
            let newWidth = max(fitting.width, 200)
            let newHeight = max(fitting.height, 40)

            // Keep horizontally centered relative to current center
            let currentCenter = panel.frame.midX
            let newX = currentCenter - newWidth / 2
            let newY = panel.frame.origin.y + (currentSize.height - newHeight)

            panel.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true, animate: true)
        }
    }
}
