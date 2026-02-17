import SwiftUI
import AppKit

// MARK: - Floating Panel

final class ExportFloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false      // CRITICAL: prevents double-free with ARC
        level = .floating
        hidesOnDeactivate = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Panel Manager

@Observable
final class ExportPanelManager {
    private(set) var isShowing = false
    private var panel: ExportFloatingPanel?

    func show(project: Project, anchorFrame: NSRect? = nil) {
        guard !isShowing else {
            dismiss()
            return
        }

        let popupView = ExportPopupView(project: project, onDismiss: { [weak self] in
            self?.dismiss()
        })

        let hostingView = NSHostingView(rootView: popupView)
        hostingView.sizingOptions = [.intrinsicContentSize]

        let fittingSize = hostingView.fittingSize
        let panelRect = NSRect(x: 0, y: 0, width: max(fittingSize.width, 320), height: max(fittingSize.height, 220))

        let floatingPanel = ExportFloatingPanel(contentRect: panelRect)
        floatingPanel.contentView = hostingView

        // Center in the main window
        if let window = NSApp.mainWindow {
            let windowFrame = window.frame
            let x = windowFrame.midX - panelRect.width / 2
            let y = windowFrame.midY - panelRect.height / 2
            floatingPanel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelRect.width / 2
            let y = screenFrame.midY - panelRect.height / 2
            floatingPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        floatingPanel.orderFrontRegardless()
        panel = floatingPanel
        isShowing = true
    }

    func dismiss() {
        panel?.close()
        panel = nil
        isShowing = false
    }
}

// MARK: - Export Popup View

struct ExportPopupView: View {
    @Bindable var project: Project
    var onDismiss: () -> Void

    private let resolutions: [(label: String, w: Double, h: Double)] = [
        ("1280 \u{00D7} 720", 1280, 720),
        ("1920 \u{00D7} 1080", 1920, 1080),
        ("2560 \u{00D7} 1440", 2560, 1440),
        ("3840 \u{00D7} 2160", 3840, 2160),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.xl) {
            // Header
            HStack {
                Text("Export")
                    .font(SB.Typo.pageTitle)
                    .foregroundStyle(SB.Colors.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SB.Colors.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            // Resolution picker
            VStack(alignment: .leading, spacing: SB.Space.md) {
                Text("Resolution")
                    .font(SB.Typo.captionMedium)
                    .foregroundStyle(SB.Colors.textSecondary)

                SBGlassTabs(
                    items: resolutions.map(\.label),
                    selection: currentResolutionLabel,
                    onSelect: { label in
                        if let res = resolutions.first(where: { $0.label == label }) {
                            project.outputWidth = res.w
                            project.outputHeight = res.h
                        }
                    }
                )
            }

            // Format label
            HStack {
                Text("Format")
                    .font(SB.Typo.captionMedium)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                SBChip(text: "H.264 MP4")
            }

            // Export button / progress
            if project.isExporting {
                VStack(spacing: SB.Space.md) {
                    ProgressView(value: project.exportProgress)
                        .tint(SB.Colors.accent)
                    Text("Exporting \(Int(project.exportProgress * 100))%")
                        .font(SB.Typo.caption)
                        .foregroundStyle(SB.Colors.textSecondary)
                }
            } else {
                SBPrimaryButton(title: "Export MP4", icon: "square.and.arrow.up", width: .infinity) {
                    project.startExport()
                    onDismiss()
                }
                .disabled(project.segments.filter(\.isEnabled).isEmpty)
            }
        }
        .padding(SB.Space.xl)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.lg, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SB.Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SB.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    private var currentResolutionLabel: String? {
        resolutions.first { $0.w == project.outputWidth && $0.h == project.outputHeight }?.label
    }
}
