import SwiftUI
import AppKit

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

        // NSColor bridge for AppKit drawing (RegionSelectionOverlay, etc.)
        static let accentNS = NSColor(red: 1.0, green: 0.35, blue: 0.37, alpha: 1.0)

        // Semantic aliases
        static let playhead = accent
    }

    // MARK: - Typography — rounded, generous, clear hierarchy

    enum Typo {
        static let heroTitle = Font.system(size: 32, weight: .bold, design: .rounded)
        static let pageTitle = Font.system(size: 22, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 13, design: .rounded)
        static let bodyMedium = Font.system(size: 13, weight: .medium, design: .rounded)
        static let bodySmall = Font.system(size: 12, design: .rounded)
        static let caption = Font.system(size: 11, design: .rounded)
        static let captionMedium = Font.system(size: 11, weight: .medium, design: .rounded)
        static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let monoMd = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let microMono = Font.system(size: 9, weight: .medium, design: .monospaced)
        static let timer = Font.system(size: 48, weight: .ultraLight, design: .monospaced)
        static let timerSm = Font.system(size: 18, weight: .light, design: .monospaced)
        static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
        static let countdown = Font.system(size: 80, weight: .ultraLight, design: .rounded)
        static let counterLg = Font.system(size: 28, weight: .light, design: .rounded)
        /// Subtitle-weight text for secondary descriptions
        static let subtitle = Font.system(size: 15, weight: .medium, design: .rounded)
    }

    // MARK: - Icon Font Sizing

    enum Icons {
        static let xs = Font.system(size: 10, weight: .medium)
        static let sm = Font.system(size: 12, weight: .semibold)
        static let md = Font.system(size: 14, weight: .medium)
        static let base = Font.system(size: 16, weight: .medium)
        static let lg = Font.system(size: 18, weight: .medium)
        static let hero = Font.system(size: 48, weight: .ultraLight)
    }

    // MARK: - Spacing — generous, breathable

    enum Space {
        static let xxs: CGFloat = 2
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
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Shadows

    enum Shadows {
        struct Preset {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }

        static let subtle = Preset(color: .black.opacity(0.2), radius: 4, x: 0, y: 1)
        static let card = Preset(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        static let cardHover = Preset(color: .black.opacity(0.28), radius: 20, x: 0, y: 8)
        static let float = Preset(color: .black.opacity(0.35), radius: 24, x: 0, y: 10)
        static let popup = Preset(color: .black.opacity(0.30), radius: 20, x: 0, y: 8)
        static let playhead = Preset(color: Colors.accent.opacity(0.5), radius: 4, x: 0, y: 0)

        static func glow(_ c: Color) -> Preset {
            Preset(color: c.opacity(0.5), radius: 4, x: 0, y: 0)
        }

        static func button(_ c: Color) -> Preset {
            Preset(color: c.opacity(0.35), radius: 6, x: 0, y: 2)
        }

        static func buttonHover(_ c: Color) -> Preset {
            Preset(color: c.opacity(0.35), radius: 12, x: 0, y: 4)
        }
    }

    // MARK: - Glass — white opacity scale for glass surfaces

    enum Glass {
        static let faint = Color.white.opacity(0.03)
        static let subtle = Color.white.opacity(0.06)
        static let base = Color.white.opacity(0.08)
        static let medium = Color.white.opacity(0.12)
        static let strong = Color.white.opacity(0.16)
    }

    // MARK: - Animation

    enum Anim {
        static let springSnappy = Animation.spring(duration: 0.3, bounce: 0.15)
        static let springGentle = Animation.spring(duration: 0.4, bounce: 0.1)
        static let springBouncy = Animation.spring(duration: 0.5, bounce: 0.25)
        static let fadeQuick = Animation.easeOut(duration: 0.15)
        static let fadeMedium = Animation.easeInOut(duration: 0.25)
        static let pulse = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        static let countTick = Animation.easeInOut(duration: 0.3)
    }

    // MARK: - Layout — structural constants

    enum Layout {
        static let controlPanelWidth: CGFloat = 316
        static let tabBarWidth: CGFloat = 36
        static let contentAreaWidth: CGFloat = 280
        static let timelineHeight: CGFloat = 200
        static let timelineHeightWithZoom: CGFloat = 240
        static let segmentTrackHeight: CGFloat = 80
        static let zoomTrackHeight: CGFloat = 36
        static let focusPickerHeight: CGFloat = 140
    }
}
