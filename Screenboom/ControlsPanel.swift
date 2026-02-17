import SwiftUI

struct ControlsPanel: View {
    @Bindable var project: Project

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SB.Space.xl) {
                backgroundSection
                layoutSection
                shadowSection
                outputSection
                exportSection
            }
            .padding(SB.Space.lg)
        }
        .sbGlassPanel()
    }

    // MARK: - Background

    var backgroundSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Background")

            HStack(spacing: SB.Space.md) {
                ColorPicker("", selection: $project.gradientColor1)
                    .labelsHidden()
                    .onChange(of: project.gradientColor1) { _, _ in project.updateVisuals() }
                ColorPicker("", selection: $project.gradientColor2)
                    .labelsHidden()
                    .onChange(of: project.gradientColor2) { _, _ in project.updateVisuals() }
            }

            SBGlassTabs(
                items: ["Dark", "Light", "Ocean"],
                selection: currentPreset,
                onSelect: { applyPreset($0) }
            )
        }
    }

    private var currentPreset: String? {
        let presets = backgroundPresets
        for (name, c1, c2) in presets {
            let nc1 = NSColor(project.gradientColor1).usingColorSpace(.sRGB)
            let nc2 = NSColor(project.gradientColor2).usingColorSpace(.sRGB)
            let pc1 = NSColor(c1).usingColorSpace(.sRGB)
            let pc2 = NSColor(c2).usingColorSpace(.sRGB)
            if let nc1, let nc2, let pc1, let pc2,
               abs(nc1.redComponent - pc1.redComponent) < 0.02,
               abs(nc1.greenComponent - pc1.greenComponent) < 0.02,
               abs(nc1.blueComponent - pc1.blueComponent) < 0.02,
               abs(nc2.redComponent - pc2.redComponent) < 0.02,
               abs(nc2.greenComponent - pc2.greenComponent) < 0.02,
               abs(nc2.blueComponent - pc2.blueComponent) < 0.02 {
                return name
            }
        }
        return nil
    }

    private var backgroundPresets: [(String, Color, Color)] {
        [
            ("Dark", Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.18, green: 0.12, blue: 0.28)),
            ("Light", Color(red: 0.92, green: 0.92, blue: 0.96), Color(red: 0.85, green: 0.88, blue: 0.95)),
            ("Ocean", Color(red: 0.05, green: 0.1, blue: 0.3), Color(red: 0.1, green: 0.2, blue: 0.5)),
        ]
    }

    private func applyPreset(_ name: String) {
        guard let preset = backgroundPresets.first(where: { $0.0 == name }) else { return }
        project.gradientColor1 = preset.1
        project.gradientColor2 = preset.2
        project.updateVisuals()
    }

    // MARK: - Layout

    var layoutSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Layout")

            sliderRow(label: "Padding", value: $project.padding, range: 0...200, step: 5) {
                project.updateVisuals()
            }
            sliderRow(label: "Corner Radius", value: $project.cornerRadius, range: 0...60, step: 1) {
                project.updateVisuals()
            }
        }
    }

    // MARK: - Shadow

    var shadowSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Shadow")

            sliderRow(label: "Radius", value: $project.shadowRadius, range: 0...80, step: 1) {
                project.updateVisuals()
            }
            sliderRow(label: "Opacity", value: $project.shadowOpacity, range: 0...1, step: 0.05, format: "%d%%", multiplier: 100) {
                project.updateVisuals()
            }
        }
    }

    // MARK: - Output

    var outputSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Output")

            Picker("", selection: Binding(
                get: { "\(Int(project.outputWidth))x\(Int(project.outputHeight))" },
                set: { val in
                    let parts = val.split(separator: "x")
                    if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
                        project.outputWidth = w
                        project.outputHeight = h
                        project.updateVisuals()
                    }
                }
            )) {
                Text("1920 \u{00D7} 1080").tag("1920x1080")
                Text("2560 \u{00D7} 1440").tag("2560x1440")
                Text("3840 \u{00D7} 2160").tag("3840x2160")
                Text("1280 \u{00D7} 720").tag("1280x720")
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: - Export

    var exportSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Export")

            if project.isExporting {
                VStack(spacing: SB.Space.sm) {
                    ProgressView(value: project.exportProgress)
                        .tint(SB.Colors.accent)
                    Text("Exporting \(Int(project.exportProgress * 100))%")
                        .font(SB.Typo.caption)
                        .foregroundStyle(SB.Colors.textSecondary)
                }
            } else {
                SBPrimaryButton(title: "Export MP4", icon: "square.and.arrow.up", width: .infinity) {
                    project.startExport()
                }
                .disabled(project.segments.filter(\.isEnabled).isEmpty)
            }
        }
    }

    // MARK: - Slider Helper

    private func sliderRow(
        label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        format: String = "%d",
        multiplier: CGFloat = 1,
        onChange: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: SB.Space.xs) {
            HStack {
                Text(label)
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                Text(String(format: format, Int(value.wrappedValue * multiplier)))
                    .font(SB.Typo.mono)
                    .foregroundStyle(SB.Colors.textTertiary)
            }
            Slider(value: value, in: range, step: step)
                .tint(SB.Colors.accent)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
    }
}
