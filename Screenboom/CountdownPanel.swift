import SwiftUI
import AppKit

// MARK: - Countdown Floating Panel

/// Click-through, invisible to recording. Shows large countdown number centered on target screen.
final class CountdownFloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = .floating
        sharingType = .none
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Countdown Model

@Observable
final class CountdownModel {
    var count: Int = 3
}

// MARK: - Countdown Panel Manager

/// Manages the lifecycle of the floating countdown overlay.
final class CountdownPanelManager {
    private var panel: CountdownFloatingPanel?
    private let model = CountdownModel()

    func show(on screen: NSScreen) {
        let view = CountdownOverlayView(model: model)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 200)

        let p = CountdownFloatingPanel()
        p.contentView = hosting

        let screenFrame = screen.frame
        let x = screenFrame.midX - 100
        let y = screenFrame.midY - 100
        p.setFrame(NSRect(x: x, y: y, width: 200, height: 200), display: true)
        p.orderFrontRegardless()

        panel = p
    }

    func updateCount(_ count: Int) {
        model.count = count
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Countdown Overlay View

struct CountdownOverlayView: View {
    var model: CountdownModel

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
                .frame(width: 140, height: 140)
                .blur(radius: 25)

            Text("\(model.count)")
                .font(SB.Typo.countdown)
                .foregroundStyle(SB.Colors.textPrimary)
                .contentTransition(.numericText())
                .animation(SB.Anim.countTick, value: model.count)
        }
        .frame(width: 200, height: 200)
    }
}
