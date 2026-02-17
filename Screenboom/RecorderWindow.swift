import SwiftUI
@preconcurrency import ScreenCaptureKit

struct RecorderWindow: View {
    var onRecordingComplete: (RecordingSession) -> Void

    @State private var recorder = ScreenRecorder()

    var body: some View {
        VStack(spacing: 0) {
            switch recorder.state {
            case .idle, .requestingPermission:
                permissionView
            case .ready:
                configurationView
            case .preparing:
                transitionView(title: "Preparing...", subtitle: "Setting up capture")
            case .recording:
                recordingView
            case .stopping:
                transitionView(title: "Finalizing...", subtitle: "Writing video file")
            case .completed(let session):
                completedView(session: session)
            case .failed(let message):
                failedView(message: message)
            }
        }
        .padding(SB.Space.xxl)
        .frame(width: 400)
        .fixedSize(horizontal: true, vertical: true)
        .background { SBPageBackground(accentOpacity: 0.02) }
        .task {
            if recorder.state == .idle {
                await recorder.requestPermission()
            }
        }
    }

    // MARK: - Permission

    private var permissionView: some View {
        VStack(spacing: SB.Space.xl) {
            ProgressView()
                .controlSize(.large)
                .tint(SB.Colors.accent)
            Text("Requesting Permission")
                .font(SB.Typo.sectionTitle)
                .foregroundStyle(SB.Colors.textPrimary)
            Text("Grant screen recording access in System Settings if prompted.")
                .font(SB.Typo.caption)
                .foregroundStyle(SB.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, SB.Space.xl)
    }

    // MARK: - Configuration

    private var configurationView: some View {
        VStack(spacing: SB.Space.xxl) {
            Text("Screen Recorder")
                .font(SB.Typo.pageTitle)
                .foregroundStyle(SB.Colors.textPrimary)

            VStack(alignment: .leading, spacing: SB.Space.xl) {
                // Source
                VStack(alignment: .leading, spacing: SB.Space.sm) {
                    SBSectionLabel(text: "Source")
                    Picker("", selection: $recorder.captureMode) {
                        ForEach(CaptureMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Display or Window picker
                if recorder.captureMode == .display {
                    displayPicker
                } else {
                    windowPicker
                }

                // Frame rate
                VStack(alignment: .leading, spacing: SB.Space.sm) {
                    SBSectionLabel(text: "Quality")
                    Picker("", selection: $recorder.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Toggles
                VStack(alignment: .leading, spacing: SB.Space.md) {
                    Toggle(isOn: $recorder.enableCursorTracking) {
                        HStack(spacing: SB.Space.sm) {
                            Image(systemName: "cursorarrow.motionlines")
                                .foregroundStyle(SB.Colors.textSecondary)
                            Text("Capture cursor metadata")
                                .font(SB.Typo.body)
                                .foregroundStyle(SB.Colors.textPrimary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(SB.Colors.accent)

                    Toggle(isOn: $recorder.includeCamera) {
                        HStack(spacing: SB.Space.sm) {
                            Image(systemName: "web.camera")
                                .foregroundStyle(SB.Colors.textTertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Camera overlay")
                                    .font(SB.Typo.body)
                                    .foregroundStyle(SB.Colors.textTertiary)
                                Text("Coming soon")
                                    .font(SB.Typo.caption)
                                    .foregroundStyle(SB.Colors.textTertiary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(true)
                }
            }

            SBPrimaryButton(title: "Start Recording", icon: "record.circle", width: .infinity) {
                Task { await recorder.startRecording() }
            }
        }
    }

    private var displayPicker: some View {
        VStack(alignment: .leading, spacing: SB.Space.sm) {
            SBSectionLabel(text: "Display")
            Picker("", selection: $recorder.selectedDisplay) {
                ForEach(recorder.availableDisplays, id: \.displayID) { display in
                    Text("\(display.width) \u{00D7} \(display.height)")
                        .tag(Optional(display))
                }
            }
            .labelsHidden()
        }
    }

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: SB.Space.sm) {
            HStack {
                SBSectionLabel(text: "Window")
                Spacer()
                Button {
                    Task { await recorder.refreshWindows() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SB.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh window list")
            }
            Picker("", selection: $recorder.selectedWindow) {
                ForEach(recorder.availableWindows, id: \.windowID) { window in
                    HStack {
                        Text(windowLabel(window))
                    }
                    .tag(Optional(window))
                }
            }
            .labelsHidden()
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: SB.Space.xxl) {
            HStack(spacing: SB.Space.sm) {
                SBPulsingDot(color: SB.Colors.accent)
                Text("Recording")
                    .font(SB.Typo.sectionTitle)
                    .foregroundStyle(SB.Colors.accent)
            }

            Text(sbFormatDurationPrecise(recorder.recordingDuration))
                .font(SB.Typo.timer)
                .foregroundStyle(SB.Colors.textPrimary)
                .contentTransition(.numericText())

            SBPrimaryButton(title: "Stop Recording", icon: "stop.circle.fill", width: .infinity) {
                Task { await recorder.stopRecording() }
            }
        }
    }

    // MARK: - Transition

    private func transitionView(title: String, subtitle: String) -> some View {
        VStack(spacing: SB.Space.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(SB.Colors.accent)
            Text(title)
                .font(SB.Typo.sectionTitle)
                .foregroundStyle(SB.Colors.textPrimary)
            Text(subtitle)
                .font(SB.Typo.caption)
                .foregroundStyle(SB.Colors.textSecondary)
        }
        .padding(.vertical, SB.Space.xl)
    }

    // MARK: - Completed

    private func completedView(session: RecordingSession) -> some View {
        VStack(spacing: SB.Space.xxl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(SB.Colors.success)

            Text("Recording Complete")
                .font(SB.Typo.pageTitle)
                .foregroundStyle(SB.Colors.textPrimary)

            HStack(spacing: SB.Space.md) {
                SBChip(text: sbFormatDuration(session.duration))
                SBChip(text: "\(Int(session.sourceSize.width))\u{00D7}\(Int(session.sourceSize.height))")
                SBChip(text: "\(Int(session.frameRate)) fps")
            }

            HStack(spacing: SB.Space.md) {
                SBSecondaryButton(title: "Record Again", icon: "arrow.counterclockwise") {
                    recorder.reset()
                }
                SBPrimaryButton(title: "Open in Editor", icon: "slider.horizontal.3") {
                    onRecordingComplete(session)
                }
            }
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: SB.Space.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(SB.Colors.warning)

            Text("Recording Failed")
                .font(SB.Typo.pageTitle)
                .foregroundStyle(SB.Colors.textPrimary)

            Text(message)
                .font(SB.Typo.body)
                .foregroundStyle(SB.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            SBSecondaryButton(title: "Try Again", icon: "arrow.counterclockwise") {
                Task { await recorder.requestPermission() }
            }
        }
    }

    // MARK: - Helpers

    private func windowLabel(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? ""
        let title = window.title ?? ""
        if !app.isEmpty && !title.isEmpty {
            return "\(app) — \(title)"
        }
        return app.isEmpty ? (title.isEmpty ? "Untitled" : title) : app
    }
}
