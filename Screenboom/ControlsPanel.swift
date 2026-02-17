import SwiftUI

struct ControlsPanel: View {
    @Bindable var project: Project

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SB.Space.md) {
                // INSPECTOR — contextual glass card at top
                inspectorSection

                // APPEARANCE
                glassCard {
                    backgroundSection
                    layoutSection
                    shadowSection
                }

                // CURSOR (conditional on cursor data)
                if project.hasCursorData {
                    glassCard {
                        cursorSection
                        clickEffectSection
                    }

                    // ZOOM
                    glassCard {
                        autoZoomSection
                    }
                }

                // OUTPUT
                glassCard {
                    outputSection
                }

                // EXPORT
                glassCard {
                    exportSection
                }
            }
            .padding(SB.Space.md)
        }
        .sbGlassPanel()
    }

    // MARK: - Glass Card Wrapper

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SB.Space.lg) {
            content()
        }
        .padding(SB.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous))
    }

    // MARK: - Inspector (contextual — zoom region only)

    @ViewBuilder
    private var inspectorSection: some View {
        if let regionID = project.selectedZoomRegionID,
           let region = project.zoomRegions.first(where: { $0.id == regionID }) {
            zoomRegionInspector(region: region)
        }
    }

    // MARK: - Zoom Region Inspector

    private func zoomRegionInspector(region: ZoomRegion) -> some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Zoom Region")

            sliderRow(
                label: "Zoom Level",
                value: Binding(
                    get: { region.zoomLevel },
                    set: { project.setZoomRegionLevel($0, for: region.id) }
                ),
                range: 1.1...4.0,
                step: 0.1,
                format: "%.1fx"
            ) {}

            // Focus point picker
            if project.videoSize.width > 0 {
                VStack(alignment: .leading, spacing: SB.Space.xs) {
                    Text("Focus Point")
                        .font(SB.Typo.caption)
                        .foregroundStyle(SB.Colors.textSecondary)
                    ZoomFocusPicker(
                        focusX: region.focusX,
                        focusY: region.focusY,
                        zoomLevel: region.zoomLevel,
                        videoSize: project.videoSize,
                        onFocusChanged: { x, y in
                            project.setZoomRegionFocus(x: x, y: y, for: region.id)
                        }
                    )
                }
            }

            Toggle(isOn: Binding(
                get: { region.isEnabled },
                set: { _ in project.toggleZoomRegion(region.id) }
            )) {
                Text("Enabled")
                    .font(SB.Typo.body)
                    .foregroundStyle(SB.Colors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(SB.Colors.accent)

            Button(action: { project.deleteZoomRegion(region.id) }) {
                Label("Delete Region", systemImage: "trash")
                    .font(SB.Typo.label)
                    .foregroundStyle(SB.Colors.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SB.Space.sm)
                    .background(
                        Capsule()
                            .fill(SB.Colors.destructive.opacity(0.1))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(SB.Colors.destructive.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(SB.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(SB.Colors.accent)
                .frame(width: 3)
                .padding(.vertical, SB.Space.sm)
        }
        .overlay(
            RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous))
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

    // MARK: - Cursor

    var cursorSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Cursor")

            cursorToggle
            if project.cursorSettings.isEnabled {
                cursorStyleTabs
                cursorSizeSlider
            }
        }
    }

    private var cursorToggle: some View {
        Toggle(isOn: Binding(
            get: { project.cursorSettings.isEnabled },
            set: { newValue in
                project.cursorSettings.isEnabled = newValue
                project.rebuildCursorOverlay()
                project.updateVisuals()
            }
        )) {
            Text("Show Cursor")
                .font(SB.Typo.body)
                .foregroundStyle(SB.Colors.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(SB.Colors.accent)
    }

    private var cursorStyleTabs: some View {
        SBGlassTabs(
            items: CursorStyle.allCases.map(\.displayName),
            selection: project.cursorSettings.style.displayName,
            onSelect: { name in
                project.cursorSettings.style = CursorStyle.fromDisplayName(name)
                project.rebuildCursorOverlay()
                project.updateVisuals()
            }
        )
    }

    private var cursorSizeSlider: some View {
        sliderRow(
            label: "Size",
            value: Binding(
                get: { project.cursorSettings.size },
                set: { project.cursorSettings.size = $0 }
            ),
            range: 0.5...3.0,
            step: 0.1,
            format: "%.1fx"
        ) {
            project.rebuildCursorOverlay()
            project.updateVisuals()
        }
    }

    // MARK: - Click Effect

    var clickEffectSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Click Effect")

            clickEffectToggle
            if project.cursorSettings.isEnabled && project.cursorSettings.clickEffectEnabled {
                clickEffectSizeSlider
            }
        }
    }

    private var clickEffectToggle: some View {
        Toggle(isOn: Binding(
            get: { project.cursorSettings.clickEffectEnabled },
            set: { newValue in
                project.cursorSettings.clickEffectEnabled = newValue
                project.rebuildCursorOverlay()
                project.updateVisuals()
            }
        )) {
            Text("Ripple on Click")
                .font(SB.Typo.body)
                .foregroundStyle(SB.Colors.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(SB.Colors.accent)
    }

    private var clickEffectSizeSlider: some View {
        sliderRow(
            label: "Ring Size",
            value: Binding(
                get: { project.cursorSettings.clickEffectMaxRadius },
                set: { project.cursorSettings.clickEffectMaxRadius = $0 }
            ),
            range: 15...80,
            step: 5
        ) {
            project.rebuildCursorOverlay()
            project.updateVisuals()
        }
    }

    // MARK: - Auto Zoom

    var autoZoomSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Auto Zoom")

            autoZoomToggle
            if project.cursorSettings.autoZoomEnabled {
                autoZoomSensitivityTabs

                SBSecondaryButton(title: "Regenerate", icon: "arrow.clockwise", compact: true) {
                    project.generateAutoZoomRegions()
                }
            }
        }
    }

    private var autoZoomToggle: some View {
        Toggle(isOn: Binding(
            get: { project.cursorSettings.autoZoomEnabled },
            set: { newValue in
                project.cursorSettings.autoZoomEnabled = newValue
                if newValue && project.zoomRegions.isEmpty {
                    project.generateAutoZoomRegions()
                } else {
                    project.rebuildCursorOverlay()
                    project.updateVisuals()
                }
            }
        )) {
            Text("Smart Zoom")
                .font(SB.Typo.body)
                .foregroundStyle(SB.Colors.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(SB.Colors.accent)
    }

    private var autoZoomSensitivityTabs: some View {
        SBGlassTabs(
            items: AutoZoomSensitivity.allCases.map(\.displayName),
            selection: project.cursorSettings.autoZoomSensitivity.displayName,
            onSelect: { name in
                if let sens = AutoZoomSensitivity.allCases.first(where: { $0.displayName == name }) {
                    project.cursorSettings.autoZoomSensitivity = sens
                    project.rebuildCursorOverlay()
                    project.updateVisuals()
                }
            }
        )
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
                sliderValueText(value: value.wrappedValue, format: format, multiplier: multiplier)
            }
            Slider(value: value, in: range, step: step)
                .tint(SB.Colors.accent)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
    }

    private func sliderValueText(value: CGFloat, format: String, multiplier: CGFloat) -> some View {
        let text: String
        if format.contains(".") {
            text = String(format: format, value * multiplier)
        } else {
            text = String(format: format, Int(value * multiplier))
        }
        return Text(text)
            .font(SB.Typo.mono)
            .foregroundStyle(SB.Colors.textTertiary)
    }
}

// MARK: - Zoom Focus Point Picker

struct ZoomFocusPicker: View {
    let focusX: Double
    let focusY: Double
    let zoomLevel: CGFloat
    let videoSize: CGSize
    let onFocusChanged: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let pickerSize = geo.size
            let scaleX = pickerSize.width / videoSize.width
            let scaleY = pickerSize.height / videoSize.height

            ZStack {
                // Video area background
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SB.Colors.surface)

                // Zoom crop area (dashed rectangle showing what's visible when zoomed)
                let cropW = videoSize.width / zoomLevel
                let cropH = videoSize.height / zoomLevel
                let cropX = max(0, min(videoSize.width - cropW, focusX - cropW / 2))
                let cropY = max(0, min(videoSize.height - cropH, focusY - cropH / 2))

                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(SB.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: cropW * scaleX, height: cropH * scaleY)
                    .position(
                        x: (cropX + cropW / 2) * scaleX,
                        y: (cropY + cropH / 2) * scaleY
                    )

                // Crop area fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(SB.Colors.accent.opacity(0.08))
                    .frame(width: cropW * scaleX, height: cropH * scaleY)
                    .position(
                        x: (cropX + cropW / 2) * scaleX,
                        y: (cropY + cropH / 2) * scaleY
                    )

                // Focus point crosshair
                let dotX = focusX * scaleX
                let dotY = focusY * scaleY

                Circle()
                    .fill(SB.Colors.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: SB.Colors.accent.opacity(0.5), radius: 4)
                    .position(x: dotX, y: dotY)

                // Crosshair lines
                Rectangle()
                    .fill(SB.Colors.accent.opacity(0.4))
                    .frame(width: 1, height: pickerSize.height)
                    .position(x: dotX, y: pickerSize.height / 2)

                Rectangle()
                    .fill(SB.Colors.accent.opacity(0.4))
                    .frame(width: pickerSize.width, height: 1)
                    .position(x: pickerSize.width / 2, y: dotY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newX = max(0, min(videoSize.width, value.location.x / scaleX))
                        let newY = max(0, min(videoSize.height, value.location.y / scaleY))
                        onFocusChanged(newX, newY)
                    }
            )
        }
        .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(SB.Colors.border, lineWidth: 0.5)
        )
    }
}
