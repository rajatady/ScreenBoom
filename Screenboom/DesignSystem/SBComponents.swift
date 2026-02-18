import SwiftUI

// MARK: - Glass Card Modifier

struct SBCardModifier: ViewModifier {
    var isHovered: Bool = false
    var cornerRadius: CGFloat = SB.Radius.lg

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .sbShadow(isHovered ? SB.Shadows.cardHover : SB.Shadows.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                isHovered ? SB.Glass.strong : SB.Glass.base,
                                isHovered ? SB.Glass.subtle : SB.Glass.faint // sb-exempt
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(SB.Anim.springSnappy, value: isHovered)
    }
}

extension View {
    func sbCard(hovered: Bool = false, cornerRadius: CGFloat = SB.Radius.lg) -> some View {
        modifier(SBCardModifier(isHovered: hovered, cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Panel (sidebar, toolbar)

struct SBGlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(SB.Glass.subtle)
                    .frame(width: 0.5)
            }
    }
}

extension View {
    func sbGlassPanel() -> some View {
        modifier(SBGlassPanel())
    }
}

// MARK: - Section Label

struct SBSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SB.Typo.captionMedium)
            .foregroundStyle(SB.Colors.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - Metadata Chip

struct SBChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SB.Typo.mono)
            .foregroundStyle(SB.Colors.textSecondary)
            .padding(.horizontal, SB.Space.sm)
            .padding(.vertical, SB.Space.xxs + 1)
            .background(
                Capsule()
                    .fill(SB.Glass.subtle)
            )
    }
}

// MARK: - Primary Action Button

struct SBPrimaryButton: View {
    let title: String
    let icon: String
    var tint: Color = SB.Colors.accent
    var width: CGFloat? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(SB.Typo.label)
                .foregroundStyle(.white) // sb-exempt — button text is always white
                .frame(width: width)
                .padding(.horizontal, SB.Space.lg)
                .padding(.vertical, SB.Space.md)
                .background(
                    Capsule()
                        .fill(isHovered ? SB.Colors.accentHover : tint)
                        .sbShadow(isHovered ? SB.Shadows.buttonHover(tint) : SB.Shadows.button(tint))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(SB.Anim.springSnappy, value: isHovered)
    }
}

// MARK: - Secondary Action Button

struct SBSecondaryButton: View {
    let title: String
    let icon: String
    var compact: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(SB.Typo.label)
                .foregroundStyle(isHovered ? SB.Colors.textPrimary : SB.Colors.textSecondary)
                .padding(.horizontal, compact ? SB.Space.md : SB.Space.lg)
                .padding(.vertical, compact ? SB.Space.sm : SB.Space.md)
                .background(
                    Capsule()
                        .fill(isHovered ? SB.Glass.medium : SB.Glass.faint) // sb-exempt
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isHovered ? SB.Glass.strong : SB.Glass.base, lineWidth: 0.5) // sb-exempt
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SB.Anim.fadeQuick, value: isHovered)
    }
}

// MARK: - Icon Button (hover-reveal actions)

struct SBIconButton: View {
    let icon: String
    var size: CGFloat = 28
    var destructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium)) // sb-exempt — dynamic size based on button size
                .foregroundStyle(destructive && isHovered ? SB.Colors.destructive : SB.Colors.textPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThickMaterial)
                        .sbShadow(SB.Shadows.subtle)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(SB.Anim.springSnappy, value: isHovered)
    }
}

// MARK: - Glass Tabs (segmented control)

struct SBGlassTabs: View {
    let items: [String]
    var selection: String?
    var onSelect: (String) -> Void

    @State private var hoveredItem: String?

    var body: some View {
        HStack(spacing: SB.Space.xxs) {
            ForEach(items, id: \.self) { item in
                tabButton(item)
            }
        }
        .padding(SB.Space.xxs)
        .background(tabBackground)
        .overlay(tabBorder)
        .animation(SB.Anim.springSnappy, value: selection)
    }

    private func tabButton(_ item: String) -> some View {
        let isSelected = selection == item
        let isHovered = hoveredItem == item
        return Button { onSelect(item) } label: {
            Text(item)
                .font(SB.Typo.captionMedium)
                .foregroundStyle(isSelected ? SB.Colors.textPrimary : SB.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SB.Space.sm)
                .background(tabItemBackground(selected: isSelected, hovered: isHovered))
        }
        .buttonStyle(.plain)
        .onHover { hoveredItem = $0 ? item : nil }
    }

    private func tabItemBackground(selected: Bool, hovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
            .fill(selected ? AnyShapeStyle(.thickMaterial) : (hovered ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear)))
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
            .fill(SB.Glass.faint) // sb-exempt
    }

    private var tabBorder: some View {
        RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
            .strokeBorder(SB.Glass.subtle, lineWidth: 0.5)
    }
}

// MARK: - Page Background

struct SBPageBackground: View {
    var accentOpacity: Double = 0.03

    var body: some View {
        ZStack {
            SB.Colors.background
            RadialGradient(
                colors: [
                    SB.Colors.accent.opacity(accentOpacity),
                    Color.clear // sb-exempt — clear is not a raw color violation
                ],
                center: .topLeading,
                startRadius: 50,
                endRadius: 700
            )
            RadialGradient(
                colors: [
                    Color.purple.opacity(accentOpacity * 0.5), // sb-exempt — ambient glow accent
                    Color.clear // sb-exempt
                ],
                center: .bottomTrailing,
                startRadius: 50,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pulsing Dot (recording indicator)

struct SBPulsingDot: View {
    let color: Color
    var size: CGFloat = 10
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.6), radius: 6) // sb-exempt — dynamic color based on prop
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(SB.Anim.pulse, value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Icon Tab Bar (vertical strip)

struct SBIconTabBar<Tab: Hashable>: View {
    let tabs: [(id: Tab, icon: String, label: String, enabled: Bool)]
    @Binding var selection: Tab

    @State private var hoveredTab: Tab?

    var body: some View {
        VStack(spacing: SB.Space.xs) {
            ForEach(tabs, id: \.id) { tab in
                tabButton(tab)
            }
        }
        .padding(.vertical, SB.Space.sm)
        .frame(width: SB.Layout.tabBarWidth)
    }

    private func tabButton(_ tab: (id: Tab, icon: String, label: String, enabled: Bool)) -> some View {
        let isSelected = selection == tab.id
        let isHovered = hoveredTab == tab.id

        return Button {
            if tab.enabled {
                selection = tab.id
            }
        } label: {
            ZStack {
                if isSelected && tab.enabled {
                    RoundedRectangle(cornerRadius: SB.Radius.xxs)
                        .fill(SB.Colors.accent)
                        .frame(width: 3, height: SB.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.scale.combined(with: .opacity))
                }

                Image(systemName: tab.icon)
                    .font(SB.Icons.md)
                    .foregroundStyle(
                        !tab.enabled ? SB.Colors.textTertiary.opacity(0.5) :
                        isSelected ? SB.Colors.accent :
                        isHovered ? SB.Colors.textPrimary :
                        SB.Colors.textSecondary
                    )
                    .frame(width: SB.Layout.tabBarWidth - SB.Space.xs, height: SB.Layout.tabBarWidth - SB.Space.xs)
            }
            .frame(width: SB.Layout.tabBarWidth, height: SB.Layout.tabBarWidth - SB.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .fill(isSelected && tab.enabled ? SB.Colors.accentSubtle : .clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor_tab_" + tab.label.lowercased().replacingOccurrences(of: " ", with: "_"))
        .onHover { hoveredTab = $0 ? tab.id : nil }
        .opacity(tab.enabled ? 1.0 : 0.3)
        .help(tab.label + (tab.enabled ? "" : " (Coming Soon)"))
        .animation(SB.Anim.springSnappy, value: isSelected)
    }
}

// MARK: - Coming Soon Placeholder

struct SBComingSoonPlaceholder: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: SB.Space.lg) {
            Spacer()

            Image(systemName: icon)
                .font(SB.Icons.hero)
                .foregroundStyle(SB.Colors.textTertiary.opacity(0.2))

            Text(title)
                .font(SB.Typo.sectionTitle)
                .foregroundStyle(SB.Colors.textTertiary.opacity(0.6))

            Text(description)
                .font(SB.Typo.caption)
                .foregroundStyle(SB.Colors.textTertiary.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)

            SBChip(text: "Coming Soon")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Glass Card Wrapper (reusable)

struct SBGlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
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
                        colors: [SB.Glass.base, SB.Glass.faint], // sb-exempt
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous))
    }
}

// MARK: - Slider Row Helper

struct SBSliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1
    var format: String = "%d"
    var multiplier: CGFloat = 1
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.xs) {
            HStack {
                Text(label)
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textSecondary)
                Spacer()
                valueText
            }
            Slider(value: $value, in: range, step: step)
                .tint(SB.Colors.accent)
                .onChange(of: value) { _, _ in onChange() }
        }
    }

    private var valueText: some View {
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

// MARK: - Option Swatch (icon grid selector)

/// Small selectable tile for type pickers — icon + label, glass background.
/// Used in grid layouts for Background Type, Frame Style, etc.
struct SBOptionSwatch: View {
    let icon: String
    let label: String
    var isSelected: Bool = false
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: SB.Space.xs) {
                Image(systemName: icon)
                    .font(SB.Icons.base)
                    .foregroundStyle(isSelected ? SB.Colors.accent : SB.Colors.textSecondary)
                    .frame(height: 20)
                Text(label)
                    .font(SB.Typo.mono)
                    .foregroundStyle(isSelected ? SB.Colors.textPrimary : SB.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SB.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .fill(isSelected ? SB.Colors.accentSubtle : (isHovered ? SB.Glass.subtle : SB.Glass.faint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected ? SB.Colors.accent.opacity(0.5) : (isHovered ? SB.Glass.medium : SB.Glass.faint), // sb-exempt
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SB.Anim.fadeQuick, value: isSelected)
        .animation(SB.Anim.fadeQuick, value: isHovered)
    }
}
