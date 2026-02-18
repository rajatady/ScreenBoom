import SwiftUI

struct AppearanceTabView: View {
    var controller: EditorSettingsController

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            // Background
            SBGlassCard {
                backgroundSection
            }

            // Frame
            SBGlassCard {
                frameSection
            }

            // Layout
            SBGlassCard {
                layoutSection
            }

            // Shadow
            SBGlassCard {
                shadowSection
            }
        }
        .accessibilityIdentifier("appearance_tab_root")
    }

    // MARK: - Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Background")

            // Visual icon grid — 5 options as small swatches
            backgroundTypeGrid

            // Conditional content based on type
            backgroundContent
        }
    }

    private var backgroundTypeGrid: some View {
        let items: [(sel: BackgroundTypeSelection, icon: String, label: String)] = [
            (.solid, "circle.fill", "Solid"),
            (.gradient, "circle.lefthalf.filled", "Gradient"),
            (.mesh, "square.grid.2x2.fill", "Mesh"),
            (.wallpaper, "photo.artframe", "Wallpaper"),
            (.image, "photo", "Image"),
        ]
        let current = controller.backgroundTypeSelection

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: SB.Space.sm),
            GridItem(.flexible(), spacing: SB.Space.sm),
            GridItem(.flexible(), spacing: SB.Space.sm),
        ], spacing: SB.Space.sm) {
            ForEach(items, id: \.sel) { item in
                SBOptionSwatch(
                    icon: item.icon,
                    label: item.label,
                    isSelected: current == item.sel
                ) {
                    controller.setBackgroundTypeSelection(item.sel)
                }
            }
        }
    }

    @ViewBuilder
    private var backgroundContent: some View {
        switch controller.backgroundTypeSelection {
        case .solid:
            HStack {
                Text("Color")
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                ColorPicker("", selection: controller.solidColorBinding())
                    .labelsHidden()
            }

        case .gradient:
            HStack(spacing: SB.Space.md) {
                VStack(spacing: SB.Space.xs) {
                    Text("Start")
                        .font(SB.Typo.mono)
                        .foregroundStyle(SB.Colors.textTertiary)
                    ColorPicker("", selection: controller.gradientColor1Binding())
                        .labelsHidden()
                }
                VStack(spacing: SB.Space.xs) {
                    Text("End")
                        .font(SB.Typo.mono)
                        .foregroundStyle(SB.Colors.textTertiary)
                    ColorPicker("", selection: controller.gradientColor2Binding())
                        .labelsHidden()
                }
                Spacer()
            }

            // Preset chips
            HStack(spacing: SB.Space.sm) {
                ForEach(EditorSettingsController.backgroundPresets, id: \.name) { preset in
                    let isActive = controller.currentPreset == preset.name
                    Button { controller.applyPreset(preset.name) } label: {
                        Text(preset.name)
                            .font(SB.Typo.captionMedium)
                            .foregroundStyle(isActive ? SB.Colors.textPrimary : SB.Colors.textSecondary)
                            .padding(.horizontal, SB.Space.sm + SB.Space.xxs) // sb-exempt — preset chip sizing
                            .padding(.vertical, SB.Space.xs + 1) // sb-exempt — preset chip sizing
                            .background(
                                Capsule()
                                    .fill(isActive ? SB.Colors.accentSubtle : SB.Glass.subtle)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isActive ? SB.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

        case .mesh:
            SBColorGrid(controller: controller)

        case .wallpaper:
            wallpaperGrid

        case .image:
            HStack(spacing: SB.Space.md) {
                SBSecondaryButton(title: "Import Image", icon: "photo", compact: true) {
                    controller.importBackgroundImage()
                }
                if case .image = controller.backgroundStyle {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SB.Colors.success)
                        .font(SB.Icons.md)
                }
            }
        }
    }

    private var wallpaperGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: SB.Space.sm),
            GridItem(.flexible(), spacing: SB.Space.sm),
            GridItem(.flexible(), spacing: SB.Space.sm),
        ], spacing: SB.Space.sm) {
            ForEach(BackgroundType.wallpaperPresets, id: \.name) { preset in
                wallpaperThumbnail(name: preset.name, style: preset.style)
            }
        }
    }

    private func wallpaperThumbnail(name: String, style: BackgroundType) -> some View {
        let isSelected: Bool = {
            if case .wallpaper(let n) = controller.backgroundStyle { return n == name }
            return false
        }()

        return Button {
            controller.selectWallpaper(name)
        } label: {
            VStack(spacing: SB.Space.xs) {
                wallpaperPreviewRect(style: style)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                            .strokeBorder(isSelected ? SB.Colors.accent : SB.Glass.base, lineWidth: isSelected ? 2 : 0.5)
                    )
                Text(name)
                    .font(SB.Typo.mono)
                    .foregroundStyle(isSelected ? SB.Colors.textPrimary : SB.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func wallpaperPreviewRect(style: BackgroundType) -> some View {
        let resolved = style.resolved()
        switch resolved {
        case .gradient(let c1, let c2):
            LinearGradient(
                colors: [c1.toColor(), c2.toColor()],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mesh(let tl, let tr, let bl, let br):
            ZStack {
                LinearGradient(colors: [bl.toColor(), tr.toColor()], startPoint: .bottomLeading, endPoint: .topTrailing)
                LinearGradient(colors: [tl.toColor().opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [br.toColor().opacity(0.5), .clear], startPoint: .bottomTrailing, endPoint: .topLeading)
            }
        default:
            SB.Colors.surface
        }
    }

    // MARK: - Frame

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Frame")

            // Visual icon grid for frame styles
            frameStyleGrid

            frameContent
        }
    }

    private var frameStyleGrid: some View {
        let items: [(sel: FrameStyleSelection, icon: String, label: String)] = [
            (.none, "xmark.circle", "None"),
            (.border, "rectangle", "Border"),
            (.glow, "sparkle", "Glow"),
            (.browser, "globe", "Browser"),
            (.window, "macwindow", "Window"),
        ]
        let current = controller.frameStyleSelection

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: SB.Space.sm),
            GridItem(.flexible(), spacing: SB.Space.sm),
            GridItem(.flexible(), spacing: SB.Space.sm),
        ], spacing: SB.Space.sm) {
            ForEach(items, id: \.sel) { item in
                SBOptionSwatch(
                    icon: item.icon,
                    label: item.label,
                    isSelected: current == item.sel
                ) {
                    controller.setFrameStyleSelection(item.sel)
                }
            }
        }
    }

    @ViewBuilder
    private var frameContent: some View {
        switch controller.frameStyleSelection {
        case .none:
            EmptyView()

        case .border:
            SBSliderRow(
                label: "Width",
                value: controller.borderWidthBinding(),
                range: 0.5...8,
                step: 0.5,
                format: "%.1f",
                multiplier: 1
            )
            HStack {
                Text("Color")
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                ColorPicker("", selection: controller.borderColorBinding())
                    .labelsHidden()
            }

        case .glow:
            HStack {
                Text("Color")
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                ColorPicker("", selection: controller.glowColorBinding())
                    .labelsHidden()
            }
            SBSliderRow(
                label: "Radius",
                value: controller.glowRadiusBinding(),
                range: 4...40,
                step: 1
            )

        case .browser, .window:
            Text(controller.frameStyleSelection == .browser ? "Browser chrome with traffic lights" : "macOS window bar with traffic lights")
                .font(SB.Typo.caption)
                .foregroundStyle(SB.Colors.textTertiary)
        }
    }

    // MARK: - Layout

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Layout")

            SBSliderRow(
                label: "Padding",
                value: controller.paddingBinding(),
                range: 0...200,
                step: 5,
                onChange: {}
            )
            SBSliderRow(
                label: "Corner Radius",
                value: controller.cornerRadiusBinding(),
                range: 0...60,
                step: 1,
                onChange: {}
            )
        }
    }

    // MARK: - Shadow

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Shadow")

            SBSliderRow(
                label: "Radius",
                value: controller.shadowRadiusBinding(),
                range: 0...80,
                step: 1,
                onChange: {}
            )
            SBSliderRow(
                label: "Opacity",
                value: controller.shadowOpacityBinding(),
                range: 0...1,
                step: 0.05,
                format: "%d%%",
                multiplier: 100,
                onChange: {}
            )
        }
    }
}

// MARK: - Mesh Color Grid

struct SBColorGrid: View {
    var controller: EditorSettingsController

    var body: some View {
        VStack(spacing: SB.Space.sm) {
            HStack(spacing: SB.Space.md) {
                colorCell(corner: .topLeft, label: "TL")
                colorCell(corner: .topRight, label: "TR")
            }
            HStack(spacing: SB.Space.md) {
                colorCell(corner: .bottomLeft, label: "BL")
                colorCell(corner: .bottomRight, label: "BR")
            }
        }
    }

    private func colorCell(corner: MeshCorner, label: String) -> some View {
        HStack(spacing: SB.Space.xs) {
            Text(label)
                .font(SB.Typo.mono)
                .foregroundStyle(SB.Colors.textTertiary)
                .frame(width: 16)
            ColorPicker("", selection: controller.meshColorBinding(corner: corner))
                .labelsHidden()
        }
    }
}
