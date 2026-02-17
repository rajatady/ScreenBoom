import SwiftUI

// MARK: - Design Tokens

/// Screenboom's design language — Airbnb-inspired warmth meets liquid glass.
/// Warm dark palette, coral accents, generous spacing, soft depth, glass surfaces.
/// Change these tokens to reskin the entire app.
enum SB {

    // MARK: - Color Palette

    enum Colors {
        // Base surfaces — warm charcoal, not cold gray
        static let background = Color(red: 0.09, green: 0.09, blue: 0.10)
        static let surface = Color(white: 0.13)
        static let surfaceRaised = Color(white: 0.16)
        static let surfaceHover = Color(white: 0.19)
        static let surfaceOverlay = Color.black.opacity(0.5)

        // Borders — warm and subtle
        static let border = Color.white.opacity(0.07)
        static let borderHover = Color.white.opacity(0.13)
        static let borderSubtle = Color.white.opacity(0.04)

        // Text — warm whites
        static let textPrimary = Color(white: 0.95)
        static let textSecondary = Color(white: 0.62)
        static let textTertiary = Color(white: 0.40)

        // Accent — warm coral (Airbnb-inspired)
        static let accent = Color(red: 1.0, green: 0.35, blue: 0.37)
        static let accentSubtle = Color(red: 1.0, green: 0.35, blue: 0.37).opacity(0.12)
        static let accentHover = Color(red: 1.0, green: 0.28, blue: 0.30)

        // Semantic
        static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
        static let warning = Color(red: 1.0, green: 0.78, blue: 0.28)
        static let destructive = Color(red: 1.0, green: 0.30, blue: 0.30)
    }

    // MARK: - Typography — rounded, generous, clear hierarchy

    enum Typo {
        static let heroTitle = Font.system(size: 32, weight: .bold, design: .rounded)
        static let pageTitle = Font.system(size: 22, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 13, design: .rounded)
        static let bodyMedium = Font.system(size: 13, weight: .medium, design: .rounded)
        static let caption = Font.system(size: 11, design: .rounded)
        static let captionMedium = Font.system(size: 11, weight: .medium, design: .rounded)
        static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let timer = Font.system(size: 48, weight: .ultraLight, design: .monospaced)
        static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
    }

    // MARK: - Spacing — generous, breathable

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Corners — rounder than typical

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Animation

    enum Anim {
        static let springSnappy = Animation.spring(duration: 0.3, bounce: 0.15)
        static let springGentle = Animation.spring(duration: 0.4, bounce: 0.1)
        static let springBouncy = Animation.spring(duration: 0.5, bounce: 0.25)
        static let fadeQuick = Animation.easeOut(duration: 0.15)
        static let fadeMedium = Animation.easeInOut(duration: 0.25)
    }
}

// MARK: - Glass Card

struct SBCardModifier: ViewModifier {
    var isHovered: Bool = false
    var cornerRadius: CGFloat = SB.Radius.lg

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.28 : 0.12),
                        radius: isHovered ? 20 : 8,
                        y: isHovered ? 8 : 3
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.16 : 0.08),
                                Color.white.opacity(isHovered ? 0.06 : 0.02)
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
                    .fill(Color.white.opacity(0.06))
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
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
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
                .foregroundStyle(.white)
                .frame(width: width)
                .padding(.horizontal, SB.Space.lg)
                .padding(.vertical, SB.Space.md)
                .background(
                    Capsule()
                        .fill(isHovered ? SB.Colors.accentHover : tint)
                        .shadow(color: tint.opacity(0.35), radius: isHovered ? 12 : 6, y: isHovered ? 4 : 2)
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
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.5)
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
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(destructive && isHovered ? SB.Colors.destructive : SB.Colors.textPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThickMaterial)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
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
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                tabButton(item)
            }
        }
        .padding(2)
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
            .fill(Color.white.opacity(0.04))
    }

    private var tabBorder: some View {
        RoundedRectangle(cornerRadius: SB.Radius.md, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
    }
}

// MARK: - Page Background

struct SBPageBackground: View {
    var accentOpacity: Double = 0.03

    var body: some View {
        ZStack {
            SB.Colors.background
            // Warm ambient glow
            RadialGradient(
                colors: [
                    SB.Colors.accent.opacity(accentOpacity),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 50,
                endRadius: 700
            )
            RadialGradient(
                colors: [
                    Color.purple.opacity(accentOpacity * 0.5),
                    Color.clear
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
            .shadow(color: color.opacity(0.6), radius: 6)
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Duration Formatter

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
        .frame(width: 36)
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
                // Accent indicator bar (left edge)
                if isSelected && tab.enabled {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(SB.Colors.accent)
                        .frame(width: 3, height: 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.scale.combined(with: .opacity))
                }

                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        !tab.enabled ? SB.Colors.textTertiary.opacity(0.5) :
                        isSelected ? SB.Colors.accent :
                        isHovered ? SB.Colors.textPrimary :
                        SB.Colors.textSecondary
                    )
                    .frame(width: 32, height: 32)
            }
            .frame(width: 36, height: 32)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .fill(isSelected && tab.enabled ? SB.Colors.accentSubtle : .clear)
            )
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 48, weight: .ultraLight))
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
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
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
                    .font(.system(size: 16, weight: .medium))
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
                    .fill(isSelected ? SB.Colors.accentSubtle : (isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SB.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected ? SB.Colors.accent.opacity(0.5) : Color.white.opacity(isHovered ? 0.1 : 0.05),
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

func sbFormatDuration(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

func sbFormatDurationPrecise(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
    return String(format: "%02d:%02d.%d", mins, secs, tenths)
}
