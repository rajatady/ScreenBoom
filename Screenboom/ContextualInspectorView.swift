import SwiftUI

struct ContextualInspectorView: View {
    var controller: EditorSettingsController

    private var project: Project { controller.project }

    var body: some View {
        VStack(spacing: 0) {
            if let region = controller.selectedZoomRegion {
                zoomRegionInspector(region: region)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let segment = controller.selectedSegment {
                segmentInspector(segment: segment)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(SB.Anim.springSnappy, value: controller.selectedZoomRegion?.id)
        .animation(SB.Anim.springSnappy, value: controller.selectedSegment?.id)
    }

    // MARK: - Zoom Region Inspector

    private func zoomRegionInspector(region: ZoomRegion) -> some View {
        inspectorCard {
            HStack {
                SBSectionLabel(text: "Zoom Region")
                Spacer()
                dismissButton
            }

            let maxTime = CGFloat(max(0.1, project.segments.last?.endTime ?? 1.0))

            SBSliderRow(
                label: "Start",
                value: Binding(
                    get: { CGFloat(region.startTime) },
                    set: { project.setZoomRegionTimes(start: Double($0), end: region.endTime, for: region.id) }
                ),
                range: 0...maxTime,
                step: 0.1,
                format: "%.1fs"
            )

            SBSliderRow(
                label: "End",
                value: Binding(
                    get: { CGFloat(region.endTime) },
                    set: { project.setZoomRegionTimes(start: region.startTime, end: Double($0), for: region.id) }
                ),
                range: 0...maxTime,
                step: 0.1,
                format: "%.1fs"
            )

            SBSliderRow(
                label: "Zoom Level",
                value: Binding(
                    get: { region.zoomLevel },
                    set: { project.setZoomRegionLevel($0, for: region.id) }
                ),
                range: 1.1...4.0,
                step: 0.1,
                format: "%.1fx"
            )

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
    }

    // MARK: - Segment Inspector

    private func segmentInspector(segment: Segment) -> some View {
        inspectorCard {
            HStack {
                SBSectionLabel(text: "Segment")
                Spacer()
                dismissButton
            }

            // Duration label
            HStack {
                Text("Duration")
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.1fs", segment.duration))
                    .font(SB.Typo.mono)
                    .foregroundStyle(SB.Colors.textTertiary)
            }

            // Speed tabs
            VStack(alignment: .leading, spacing: SB.Space.sm) {
                Text("Speed")
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)

                SBGlassTabs(
                    items: ["0.5x", "1x", "2x", "4x"],
                    selection: speedTabSelection(segment.speed),
                    onSelect: { name in
                        let speed = speedFromTab(name)
                        controller.setSegmentSpeed(speed, for: segment.id)
                    }
                )

                // Custom speed slider
                SBSliderRow(
                    label: "Custom",
                    value: Binding(
                        get: { CGFloat(segment.speed) },
                        set: { controller.setSegmentSpeed(Double($0), for: segment.id) }
                    ),
                    range: 0.25...8.0,
                    step: 0.25,
                    format: "%.2fx"
                )
            }

            Toggle(isOn: Binding(
                get: { segment.isEnabled },
                set: { _ in controller.toggleSegment(segment.id) }
            )) {
                Text("Enabled")
                    .font(SB.Typo.body)
                    .foregroundStyle(SB.Colors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(SB.Colors.accent)
        }
    }

    // MARK: - Helpers

    private var dismissButton: some View {
        Button(action: { controller.dismissInspector() }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SB.Colors.textTertiary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func inspectorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            content()
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

    private func speedTabSelection(_ speed: Double) -> String? {
        switch speed {
        case 0.5: return "0.5x"
        case 1.0: return "1x"
        case 2.0: return "2x"
        case 4.0: return "4x"
        default: return nil
        }
    }

    private func speedFromTab(_ name: String) -> Double {
        switch name {
        case "0.5x": return 0.5
        case "1x": return 1.0
        case "2x": return 2.0
        case "4x": return 4.0
        default: return 1.0
        }
    }
}
