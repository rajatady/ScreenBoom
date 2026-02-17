import SwiftUI
@preconcurrency import ScreenCaptureKit

// MARK: - Recorder Bar View

/// Compact horizontal floating bar for screen recording.
/// Reads all state from RecorderFlowController — zero business logic here.
/// Hosted inside RecorderFloatingPanel (NSPanel).
struct RecorderBarView: View {
    @State var flow: RecorderFlowController
    var onComplete: (RecordingSession) -> Void
    var onDismiss: () -> Void

    var body: some View {
        Group {
            switch flow.flowState {
            case .idle, .requestingPermission:
                permissionContent
            case .configuring, .selectingRegion:
                configContent
            case .countdown(let count):
                countdownContent(count)
            case .preparing:
                statusContent(text: "Preparing...")
            case .recording:
                recordingContent
            case .stopping:
                statusContent(text: "Finalizing...")
            case .completed(let session):
                Color.clear.frame(width: 0, height: 0)
                    .onAppear { onComplete(session) }
            case .failed(let message):
                failedContent(message: message)
            }
        }
        .padding(.horizontal, SB.Space.xl)
        .padding(.vertical, SB.Space.lg)
        .background(barBackground)
        .fixedSize()
        .task {
            if flow.flowState == .idle {
                await flow.requestPermission()
            }
        }
    }

    // MARK: - Permission

    private var permissionContent: some View {
        HStack(spacing: SB.Space.md) {
            ProgressView()
                .controlSize(.small)
                .tint(SB.Colors.accent)
            Text("Requesting permission...")
                .font(SB.Typo.bodyMedium)
                .foregroundStyle(SB.Colors.textSecondary)
        }
    }

    // MARK: - Configuration

    private var configContent: some View {
        HStack(spacing: SB.Space.lg) {
            closeButton

            thinDivider

            SBGlassTabs(
                items: CaptureMode.allCases.map(\.rawValue),
                selection: flow.captureMode.rawValue
            ) { selected in
                if let mode = CaptureMode(rawValue: selected) {
                    flow.captureMode = mode
                }
            }
            .frame(width: 220)

            thinDivider

            contextArea

            thinDivider

            startButton
        }
    }

    @ViewBuilder
    private var contextArea: some View {
        switch flow.captureMode {
        case .display:
            sourcePicker
        case .window:
            sourcePicker
        case .region:
            regionArea
        }
    }

    private var sourcePicker: some View {
        Menu {
            if flow.captureMode == .display {
                ForEach(flow.availableDisplays, id: \.displayID) { display in
                    Button("\(display.width) \u{00D7} \(display.height)") {
                        flow.selectedDisplay = display
                    }
                }
            } else if flow.captureMode == .window {
                ForEach(flow.availableWindows, id: \.windowID) { window in
                    Button(windowLabel(window)) {
                        flow.selectedWindow = window
                    }
                }
                Divider()
                Button {
                    Task { await flow.refreshWindows() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            HStack(spacing: SB.Space.sm) {
                Image(systemName: flow.captureMode == .display ? "display" : "macwindow")
                    .font(SB.Icons.sm)
                    .foregroundStyle(SB.Colors.textTertiary)
                Text(sourceLabel)
                    .font(SB.Typo.bodyMedium)
                    .foregroundStyle(SB.Colors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(SB.Icons.xs)
                    .foregroundStyle(SB.Colors.textTertiary)
            }
            .padding(.horizontal, SB.Space.md)
            .padding(.vertical, SB.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .fill(SB.Glass.subtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .strokeBorder(SB.Glass.base, lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var regionArea: some View {
        if let region = flow.selectedRegion {
            // Clickable dimension chip — tap to re-select region
            Button {
                flow.beginRegionSelection()
            } label: {
                HStack(spacing: SB.Space.sm) {
                    Image(systemName: "rectangle.dashed")
                        .font(SB.Icons.sm)
                        .foregroundStyle(SB.Colors.accent)
                    Text("\(Int(region.width))\u{00D7}\(Int(region.height))")
                        .font(SB.Typo.monoMd)
                        .foregroundStyle(SB.Colors.textPrimary)
                }
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                        .fill(SB.Colors.accentSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                        .strokeBorder(SB.Colors.accent.opacity(0.2), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        } else if flow.flowState == .selectingRegion {
            // Overlay is active
            HStack(spacing: SB.Space.sm) {
                ProgressView()
                    .controlSize(.small)
                    .tint(SB.Colors.accent)
                Text("Select area...")
                    .font(SB.Typo.bodyMedium)
                    .foregroundStyle(SB.Colors.textSecondary)
            }
        } else {
            // Cancelled or fallback — clickable to retry
            Button {
                flow.beginRegionSelection()
            } label: {
                HStack(spacing: SB.Space.sm) {
                    Image(systemName: "rectangle.dashed")
                        .font(SB.Icons.sm)
                        .foregroundStyle(SB.Colors.textTertiary)
                    Text("Select area")
                        .font(SB.Typo.bodyMedium)
                        .foregroundStyle(SB.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var startButton: some View {
        Button {
            flow.initiateRecording()
        } label: {
            HStack(spacing: SB.Space.sm) {
                Circle()
                    .fill(flow.canStart ? SB.Colors.accent : SB.Colors.textTertiary)
                    .frame(width: 8, height: 8)
                Text("Start")
                    .font(SB.Typo.label)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, SB.Space.lg)
            .padding(.vertical, SB.Space.md)
            .background(
                Capsule()
                    .fill(flow.canStart ? SB.Colors.accent : SB.Colors.textTertiary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .disabled(!flow.canStart)
    }

    // MARK: - Countdown

    private func countdownContent(_ count: Int) -> some View {
        HStack(spacing: SB.Space.lg) {
            Text("\(count)")
                .font(SB.Typo.counterLg)
                .foregroundStyle(SB.Colors.accent)
                .contentTransition(.numericText())
                .frame(width: 32)

            Text("Recording starts in \(count)...")
                .font(SB.Typo.bodyMedium)
                .foregroundStyle(SB.Colors.textSecondary)

            thinDivider

            SBIconButton(icon: "xmark", size: 26) {
                flow.cancelCountdown()
            }
        }
        .animation(SB.Anim.countTick, value: count)
    }

    // MARK: - Recording

    private var recordingContent: some View {
        HStack(spacing: SB.Space.lg) {
            SBPulsingDot(color: SB.Colors.accent, size: 8)

            Text(sbFormatDurationPrecise(flow.recordingDuration))
                .font(SB.Typo.timerSm)
                .foregroundStyle(SB.Colors.textPrimary)
                .contentTransition(.numericText())

            thinDivider

            Button {
                Task { await flow.stopRecording() }
            } label: {
                HStack(spacing: SB.Space.sm) {
                    RoundedRectangle(cornerRadius: SB.Radius.xxs)
                        .fill(SB.Colors.textPrimary)
                        .frame(width: 10, height: 10)
                    Text("Stop")
                        .font(SB.Typo.label)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, SB.Space.lg)
                .padding(.vertical, SB.Space.md)
                .background(
                    Capsule()
                        .fill(SB.Colors.accent)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Status (preparing / stopping)

    private func statusContent(text: String) -> some View {
        HStack(spacing: SB.Space.md) {
            ProgressView()
                .controlSize(.small)
                .tint(SB.Colors.accent)
            Text(text)
                .font(SB.Typo.bodyMedium)
                .foregroundStyle(SB.Colors.textSecondary)
        }
    }

    // MARK: - Failed

    private func failedContent(message: String) -> some View {
        HStack(spacing: SB.Space.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(SB.Icons.base)
                .foregroundStyle(SB.Colors.warning)

            Text(message)
                .font(SB.Typo.caption)
                .foregroundStyle(SB.Colors.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: 240)

            thinDivider

            Button("Retry") {
                Task { await flow.requestPermission() }
            }
            .font(SB.Typo.label)
            .foregroundStyle(SB.Colors.accent)
            .buttonStyle(.plain)

            closeButton
        }
    }

    // MARK: - Shared Components

    private var closeButton: some View {
        SBIconButton(icon: "xmark", size: 26) {
            onDismiss()
        }
    }

    private var thinDivider: some View {
        RoundedRectangle(cornerRadius: 0.5) // sb-exempt — sub-pixel radius
            .fill(SB.Glass.base)
            .frame(width: 1, height: SB.Space.xl)
    }

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: SB.Radius.xl, style: .continuous)
            .fill(.ultraThinMaterial)
            .sbShadow(SB.Shadows.float)
            .overlay(
                RoundedRectangle(cornerRadius: SB.Radius.xl, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                SB.Glass.strong, // sb-exempt
                                SB.Glass.faint   // sb-exempt
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Helpers

    private var sourceLabel: String {
        switch flow.captureMode {
        case .display:
            if let d = flow.selectedDisplay {
                return "\(d.width) \u{00D7} \(d.height)"
            }
            return "Display"
        case .window:
            if let w = flow.selectedWindow {
                return windowLabel(w)
            }
            return "Window"
        case .region:
            return "Region"
        }
    }

    private func windowLabel(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? ""
        let title = window.title ?? ""
        if !app.isEmpty && !title.isEmpty {
            return "\(app) — \(title)"
        }
        return app.isEmpty ? (title.isEmpty ? "Untitled" : title) : app
    }
}
