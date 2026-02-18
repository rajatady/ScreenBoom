import SwiftUI

struct ZoomTabView: View {
    var controller: EditorSettingsController

    private var project: Project { controller.project }

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBGlassCard {
                autoZoomSection
            }
        }
        .accessibilityIdentifier("zoom_tab_root")
    }

    // MARK: - Auto Zoom

    private var autoZoomSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Auto Zoom")

            Toggle(isOn: Binding(
                get: { project.cursorSettings.autoZoomEnabled },
                set: { controller.setAutoZoomEnabled($0) }
            )) {
                Text("Smart Zoom")
                    .font(SB.Typo.body)
                    .foregroundStyle(SB.Colors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(SB.Colors.accent)

            if project.cursorSettings.autoZoomEnabled {
                SBGlassTabs(
                    items: AutoZoomSensitivity.allCases.map(\.displayName),
                    selection: project.cursorSettings.autoZoomSensitivity.displayName,
                    onSelect: { name in
                        if let sens = AutoZoomSensitivity.allCases.first(where: { $0.displayName == name }) {
                            controller.setAutoZoomSensitivity(sens)
                        }
                    }
                )

                SBSliderRow(
                    label: "Default Zoom",
                    value: controller.autoZoomLevelBinding(),
                    range: 1.1...4.0,
                    step: 0.1,
                    format: "%.1fx"
                )

                SBSecondaryButton(title: "Regenerate", icon: "arrow.clockwise", compact: true) {
                    controller.regenerateZoomRegions()
                }
            }
        }
    }
}
