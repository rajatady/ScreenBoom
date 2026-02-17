import SwiftUI

struct AppearanceTabView: View {
    var controller: EditorSettingsController

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            // Background
            SBGlassCard {
                backgroundSection
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
    }

    // MARK: - Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Background")

            HStack(spacing: SB.Space.md) {
                ColorPicker("", selection: controller.gradientColor1Binding())
                    .labelsHidden()
                ColorPicker("", selection: controller.gradientColor2Binding())
                    .labelsHidden()
            }

            SBGlassTabs(
                items: EditorSettingsController.backgroundPresets.map(\.name),
                selection: controller.currentPreset,
                onSelect: { controller.applyPreset($0) }
            )
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
