import Foundation
import SwiftUI
import CoreImage
import AppKit

// MARK: - CodableColor

struct CodableColor: Codable, Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    nonisolated init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    nonisolated init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = c.redComponent
        self.green = c.greenComponent
        self.blue = c.blueComponent
        self.alpha = c.alphaComponent
    }

    nonisolated init(swiftUI color: Color) {
        self.init(nsColor: NSColor(color))
    }

    nonisolated func toNSColor() -> NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    nonisolated func toCIColor() -> CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    nonisolated func toColor() -> Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - BackgroundType

enum BackgroundType: Codable, Sendable, Equatable {
    case solid(CodableColor)
    case gradient(CodableColor, CodableColor)
    case mesh(topLeft: CodableColor, topRight: CodableColor,
              bottomLeft: CodableColor, bottomRight: CodableColor)
    case wallpaper(String)
    case image(Data)

    // MARK: - Default

    static let defaultStyle: BackgroundType = .gradient(
        CodableColor(red: 0.08, green: 0.08, blue: 0.12),
        CodableColor(red: 0.18, green: 0.12, blue: 0.28)
    )

    // MARK: - Wallpaper Presets

    static let wallpaperPresets: [(name: String, style: BackgroundType)] = [
        ("Sunset", .mesh(
            topLeft: CodableColor(red: 1.0, green: 0.55, blue: 0.20),
            topRight: CodableColor(red: 0.95, green: 0.25, blue: 0.40),
            bottomLeft: CodableColor(red: 0.85, green: 0.35, blue: 0.55),
            bottomRight: CodableColor(red: 0.45, green: 0.15, blue: 0.60)
        )),
        ("Aurora", .mesh(
            topLeft: CodableColor(red: 0.05, green: 0.80, blue: 0.55),
            topRight: CodableColor(red: 0.10, green: 0.45, blue: 0.85),
            bottomLeft: CodableColor(red: 0.02, green: 0.15, blue: 0.35),
            bottomRight: CodableColor(red: 0.30, green: 0.10, blue: 0.60)
        )),
        ("Midnight", .gradient(
            CodableColor(red: 0.02, green: 0.02, blue: 0.08),
            CodableColor(red: 0.10, green: 0.05, blue: 0.22)
        )),
        ("Lavender", .mesh(
            topLeft: CodableColor(red: 0.75, green: 0.60, blue: 0.95),
            topRight: CodableColor(red: 0.55, green: 0.45, blue: 0.90),
            bottomLeft: CodableColor(red: 0.90, green: 0.70, blue: 0.85),
            bottomRight: CodableColor(red: 0.65, green: 0.50, blue: 0.95)
        )),
        ("Forest", .mesh(
            topLeft: CodableColor(red: 0.05, green: 0.25, blue: 0.10),
            topRight: CodableColor(red: 0.10, green: 0.35, blue: 0.15),
            bottomLeft: CodableColor(red: 0.02, green: 0.12, blue: 0.08),
            bottomRight: CodableColor(red: 0.08, green: 0.20, blue: 0.12)
        )),
        ("Ocean Deep", .mesh(
            topLeft: CodableColor(red: 0.02, green: 0.15, blue: 0.40),
            topRight: CodableColor(red: 0.05, green: 0.25, blue: 0.55),
            bottomLeft: CodableColor(red: 0.01, green: 0.08, blue: 0.25),
            bottomRight: CodableColor(red: 0.03, green: 0.18, blue: 0.45)
        )),
        ("Rose Gold", .mesh(
            topLeft: CodableColor(red: 0.90, green: 0.70, blue: 0.60),
            topRight: CodableColor(red: 0.85, green: 0.55, blue: 0.50),
            bottomLeft: CodableColor(red: 0.75, green: 0.50, blue: 0.45),
            bottomRight: CodableColor(red: 0.65, green: 0.40, blue: 0.40)
        )),
        ("Slate", .gradient(
            CodableColor(red: 0.22, green: 0.24, blue: 0.28),
            CodableColor(red: 0.12, green: 0.13, blue: 0.16)
        )),
        ("Neon City", .mesh(
            topLeft: CodableColor(red: 0.90, green: 0.10, blue: 0.55),
            topRight: CodableColor(red: 0.15, green: 0.10, blue: 0.45),
            bottomLeft: CodableColor(red: 0.10, green: 0.05, blue: 0.30),
            bottomRight: CodableColor(red: 0.05, green: 0.85, blue: 0.90)
        )),
        ("Ember", .mesh(
            topLeft: CodableColor(red: 0.95, green: 0.35, blue: 0.10),
            topRight: CodableColor(red: 0.80, green: 0.20, blue: 0.05),
            bottomLeft: CodableColor(red: 0.55, green: 0.10, blue: 0.05),
            bottomRight: CodableColor(red: 0.30, green: 0.05, blue: 0.02)
        )),
    ]

    nonisolated static func wallpaperByName(_ name: String) -> BackgroundType? {
        wallpaperPresets.first { $0.name == name }?.style
    }

    /// Resolve wallpaper references to their underlying style.
    nonisolated func resolved() -> BackgroundType {
        if case .wallpaper(let name) = self {
            return Self.wallpaperByName(name) ?? .defaultStyle
        }
        return self
    }
}

// MARK: - FrameStyle

enum FrameStyle: Codable, Sendable, Equatable {
    case none
    case border(width: CGFloat, color: CodableColor)
    case gradientBorder(width: CGFloat, color1: CodableColor, color2: CodableColor)
    case neonGlow(color: CodableColor, radius: CGFloat)
    case browserChrome
    case macOSWindow

    nonisolated var chromeHeight: CGFloat {
        switch self {
        case .browserChrome: 40
        case .macOSWindow: 28
        default: 0
        }
    }
}
