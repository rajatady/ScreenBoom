import SwiftUI

struct CursorTabView: View {
    var controller: EditorSettingsController

    private var project: Project { controller.project }

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            // Cursor
            SBGlassCard {
                cursorSection
            }
            .accessibilityIdentifier("cursor_section")

            // Click Effect
            SBGlassCard {
                clickEffectSection
            }
            .accessibilityIdentifier("cursor_click_effect_section")
        }
    }

    // MARK: - Cursor

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Cursor")

            Toggle(isOn: Binding(
                get: { project.cursorSettings.isEnabled },
                set: { controller.setCursorEnabled($0) }
            )) {
                Text("Show Cursor")
                    .font(SB.Typo.body)
                    .foregroundStyle(SB.Colors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(SB.Colors.accent)

            if project.cursorSettings.isEnabled {
                SBGlassTabs(
                    items: CursorStyle.allCases.map(\.displayName),
                    selection: project.cursorSettings.style.displayName,
                    onSelect: { name in
                        controller.setCursorStyle(CursorStyle.fromDisplayName(name))
                    }
                )

                SBSliderRow(
                    label: "Size",
                    value: Binding(
                        get: { project.cursorSettings.size },
                        set: { controller.setCursorSize($0) }
                    ),
                    range: 0.5...3.0,
                    step: 0.1,
                    format: "%.1fx"
                )
            }
        }
    }

    // MARK: - Click Effect

    private var clickEffectSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            SBSectionLabel(text: "Click Effect")

            Toggle(isOn: Binding(
                get: { project.cursorSettings.clickEffectEnabled },
                set: { controller.setClickEffectEnabled($0) }
            )) {
                Text("Ripple on Click")
                    .font(SB.Typo.body)
                    .foregroundStyle(SB.Colors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(SB.Colors.accent)

            if project.cursorSettings.isEnabled && project.cursorSettings.clickEffectEnabled {
                SBSliderRow(
                    label: "Ring Size",
                    value: Binding(
                        get: { project.cursorSettings.clickEffectMaxRadius },
                        set: { controller.setClickEffectRadius($0) }
                    ),
                    range: 15...80,
                    step: 5
                )
            }
        }
    }
}
