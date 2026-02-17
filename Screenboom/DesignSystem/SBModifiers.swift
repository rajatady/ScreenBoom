import SwiftUI

// MARK: - Shadow Modifier

struct SBShadowModifier: ViewModifier {
    let preset: SB.Shadows.Preset

    func body(content: Content) -> some View {
        content.shadow(
            color: preset.color,
            radius: preset.radius,
            x: preset.x,
            y: preset.y
        )
    }
}

// MARK: - Page Background Modifier

struct SBPageBackgroundModifier: ViewModifier {
    var accentOpacity: Double = 0.03

    func body(content: Content) -> some View {
        content.background { SBPageBackground(accentOpacity: accentOpacity) }
    }
}

// MARK: - View Extensions

extension View {
    func sbShadow(_ preset: SB.Shadows.Preset) -> some View {
        modifier(SBShadowModifier(preset: preset))
    }

    func sbPageBackground(accentOpacity: Double = 0.03) -> some View {
        modifier(SBPageBackgroundModifier(accentOpacity: accentOpacity))
    }
}
