import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Screenboom

struct BackgroundModelTests {

    // MARK: - CodableColor

    @Test func codableColorRoundTripFromNSColor() throws {
        let original = NSColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.8)
        let codable = CodableColor(nsColor: original)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)
        #expect(abs(decoded.red - 0.3) < 0.01)
        #expect(abs(decoded.green - 0.6) < 0.01)
        #expect(abs(decoded.blue - 0.9) < 0.01)
        #expect(abs(decoded.alpha - 0.8) < 0.01)
    }

    @Test func codableColorRoundTripFromSwiftUI() throws {
        let swiftUIColor = Color(red: 0.5, green: 0.2, blue: 0.8)
        let codable = CodableColor(swiftUI: swiftUIColor)
        let roundTripped = codable.toColor()
        // Convert back to NSColor for comparison
        let ns1 = NSColor(roundTripped).usingColorSpace(.sRGB)!
        #expect(abs(ns1.redComponent - 0.5) < 0.02)
        #expect(abs(ns1.greenComponent - 0.2) < 0.02)
        #expect(abs(ns1.blueComponent - 0.8) < 0.02)
    }

    @Test func codableColorEquality() {
        let a = CodableColor(red: 0.5, green: 0.5, blue: 0.5)
        let b = CodableColor(red: 0.5, green: 0.5, blue: 0.5)
        let c = CodableColor(red: 0.6, green: 0.5, blue: 0.5)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func codableColorToCIColor() {
        let c = CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9)
        let ci = c.toCIColor()
        #expect(abs(ci.red - 0.1) < 0.001)
        #expect(abs(ci.green - 0.2) < 0.001)
        #expect(abs(ci.blue - 0.3) < 0.001)
        #expect(abs(ci.alpha - 0.9) < 0.001)
    }

    // MARK: - BackgroundType Codable Round-Trips

    @Test func solidBackgroundRoundTrip() throws {
        let style = BackgroundType.solid(CodableColor(red: 0.1, green: 0.2, blue: 0.3))
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BackgroundType.self, from: data)
        #expect(decoded == style)
    }

    @Test func gradientBackgroundRoundTrip() throws {
        let style = BackgroundType.gradient(
            CodableColor(red: 0.1, green: 0.2, blue: 0.3),
            CodableColor(red: 0.4, green: 0.5, blue: 0.6)
        )
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BackgroundType.self, from: data)
        #expect(decoded == style)
    }

    @Test func meshBackgroundRoundTrip() throws {
        let style = BackgroundType.mesh(
            topLeft: CodableColor(red: 1, green: 0, blue: 0),
            topRight: CodableColor(red: 0, green: 1, blue: 0),
            bottomLeft: CodableColor(red: 0, green: 0, blue: 1),
            bottomRight: CodableColor(red: 1, green: 1, blue: 0)
        )
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BackgroundType.self, from: data)
        #expect(decoded == style)
    }

    @Test func wallpaperBackgroundRoundTrip() throws {
        let style = BackgroundType.wallpaper("Sunset")
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BackgroundType.self, from: data)
        #expect(decoded == style)
    }

    @Test func imageBackgroundRoundTrip() throws {
        let style = BackgroundType.image(Data([0x01, 0x02, 0x03]))
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BackgroundType.self, from: data)
        #expect(decoded == style)
    }

    // MARK: - FrameStyle Codable Round-Trips

    @Test func frameStyleNoneRoundTrip() throws {
        let style = FrameStyle.none
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(FrameStyle.self, from: data)
        #expect(decoded == style)
    }

    @Test func frameStyleBorderRoundTrip() throws {
        let style = FrameStyle.border(width: 3.0, color: CodableColor(red: 1, green: 0, blue: 0))
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(FrameStyle.self, from: data)
        #expect(decoded == style)
    }

    @Test func frameStyleBrowserChromeRoundTrip() throws {
        let style = FrameStyle.browserChrome
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(FrameStyle.self, from: data)
        #expect(decoded == style)
    }

    // MARK: - Chrome Height

    @Test func chromeHeightCorrectForAllStyles() {
        #expect(FrameStyle.none.chromeHeight == 0)
        #expect(FrameStyle.border(width: 2, color: CodableColor(red: 0, green: 0, blue: 0)).chromeHeight == 0)
        #expect(FrameStyle.neonGlow(color: CodableColor(red: 1, green: 0, blue: 1), radius: 10).chromeHeight == 0)
        #expect(FrameStyle.browserChrome.chromeHeight == 40)
        #expect(FrameStyle.macOSWindow.chromeHeight == 28)
    }

    // MARK: - Wallpaper Presets

    @Test func wallpaperPresetLookupByName() {
        for preset in BackgroundType.wallpaperPresets {
            let resolved = BackgroundType.wallpaperByName(preset.name)
            #expect(resolved != nil, "Preset '\(preset.name)' should resolve")
        }
    }

    @Test func wallpaperPresetCount() {
        #expect(BackgroundType.wallpaperPresets.count == 10)
    }

    @Test func wallpaperResolvedReturnsUnderlyingStyle() {
        let wallpaper = BackgroundType.wallpaper("Sunset")
        let resolved = wallpaper.resolved()
        if case .mesh = resolved {
            // Sunset is a mesh — correct
        } else {
            Issue.record("Expected Sunset to resolve to .mesh, got \(resolved)")
        }
    }

    @Test func nonWallpaperResolvedReturnsSelf() {
        let solid = BackgroundType.solid(CodableColor(red: 1, green: 0, blue: 0))
        #expect(solid.resolved() == solid)
    }
}
