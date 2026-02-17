import SwiftUI

struct ControlsPanel: View {
    var controller: EditorSettingsController

    var body: some View {
        HStack(spacing: 0) {
            // Vertical icon tab bar
            SBIconTabBar(
                tabs: controller.availableTabs.map { tab in
                    (id: tab, icon: tab.icon, label: tab.label, enabled: !tab.isComingSoon)
                },
                selection: Binding(
                    get: { controller.selectedTab },
                    set: { controller.selectedTab = $0 }
                )
            )
            .padding(.top, SB.Space.sm)

            // Thin separator
            Rectangle()
                .fill(SB.Glass.subtle)
                .frame(width: 0.5)

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: SB.Space.md) {
                    // Contextual inspector (slides in from top)
                    ContextualInspectorView(controller: controller)

                    // Tab content
                    tabContent
                }
                .padding(SB.Space.md)
            }
        }
        .sbGlassPanel()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch controller.selectedTab {
        case .appearance:
            AppearanceTabView(controller: controller)
        case .cursor:
            CursorTabView(controller: controller)
        case .zoom:
            ZoomTabView(controller: controller)
        case .audio:
            SBComingSoonPlaceholder(
                icon: "waveform",
                title: "Audio",
                description: "Audio mixing, music tracks, and sound effects"
            )
        case .annotations:
            SBComingSoonPlaceholder(
                icon: "pencil.tip.crop.circle",
                title: "Annotations",
                description: "Arrows, callouts, highlights, and text overlays"
            )
        case .subtitles:
            SBComingSoonPlaceholder(
                icon: "captions.bubble",
                title: "Subtitles",
                description: "Auto-generated captions and subtitle tracks"
            )
        }
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
                RoundedRectangle(cornerRadius: SB.Radius.xs, style: .continuous)
                    .fill(SB.Colors.surface)

                // Zoom crop area (dashed rectangle showing what's visible when zoomed)
                let cropW = videoSize.width / zoomLevel
                let cropH = videoSize.height / zoomLevel
                let cropX = max(0, min(videoSize.width - cropW, focusX - cropW / 2))
                let cropY = max(0, min(videoSize.height - cropH, focusY - cropH / 2))

                RoundedRectangle(cornerRadius: SB.Radius.xxs)
                    .strokeBorder(SB.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: cropW * scaleX, height: cropH * scaleY)
                    .position(
                        x: (cropX + cropW / 2) * scaleX,
                        y: (cropY + cropH / 2) * scaleY
                    )

                // Crop area fill
                RoundedRectangle(cornerRadius: SB.Radius.xxs)
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
                    .sbShadow(SB.Shadows.glow(SB.Colors.accent))
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
        .frame(height: SB.Layout.focusPickerHeight)
        .clipShape(RoundedRectangle(cornerRadius: SB.Radius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SB.Radius.xs, style: .continuous)
                .strokeBorder(SB.Colors.border, lineWidth: 0.5)
        )
    }
}
