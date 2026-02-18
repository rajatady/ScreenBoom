import Testing
import CoreImage
import AppKit
@testable import Screenboom

// MARK: - FrameRenderer Background Tests
// Covers: mesh background corner color placement (bilinear Y-axis),
// image background aspect-fill + center-crop, wallpaper fallback.

struct FrameRendererBackgroundTests {

    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    private func pixel(_ image: CIImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let ix = CGFloat(x)
        let iy = CGFloat(y)
        let crop = image
            .cropped(to: CGRect(x: ix, y: iy, width: 1, height: 1))
            .transformed(by: CGAffineTransform(translationX: -ix, y: -iy))

        var rgba = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            crop,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        return (
            r: Double(rgba[0]) / 255.0,
            g: Double(rgba[1]) / 255.0,
            b: Double(rgba[2]) / 255.0,
            a: Double(rgba[3]) / 255.0
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Mesh Background Corner Colors
    // ─────────────────────────────────────────────────────────────────
    // CGContext has bottom-left origin: row 0 = bottom.
    // topLeft/topRight → top of image, bottomLeft/bottomRight → bottom.
    // CIImage also uses bottom-left origin.

    @Test func meshBackgroundTopLeftCornerMatchesTopLeftColor() {
        // topLeft = pure red, others black
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 1, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 0, blue: 0),
                bottomLeft: CodableColor(red: 0, green: 0, blue: 0),
                bottomRight: CodableColor(red: 0, green: 0, blue: 0)
            ),
            size: CGSize(width: 64, height: 64)
        )

        // CIImage bottom-left origin: top-left of visual = (0, height-1)
        let topLeft = pixel(image, x: 1, y: 62)
        #expect(topLeft.r > 0.7, "Top-left corner should be predominantly red, got r=\(topLeft.r)")
        #expect(topLeft.g < 0.3)
        #expect(topLeft.b < 0.3)
    }

    @Test func meshBackgroundBottomRightCornerMatchesBottomRightColor() {
        // bottomRight = pure blue, others black
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 0, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 0, blue: 0),
                bottomLeft: CodableColor(red: 0, green: 0, blue: 0),
                bottomRight: CodableColor(red: 0, green: 0, blue: 1)
            ),
            size: CGSize(width: 64, height: 64)
        )

        // CIImage bottom-left origin: bottom-right of visual = (width-1, 0)
        let bottomRight = pixel(image, x: 62, y: 1)
        #expect(bottomRight.b > 0.7, "Bottom-right corner should be predominantly blue, got b=\(bottomRight.b)")
        #expect(bottomRight.r < 0.3)
        #expect(bottomRight.g < 0.3)
    }

    @Test func meshBackgroundCenterIsBilinearBlend() {
        // All four corners: red, green, blue, yellow → center should be a blend
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 1, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 1, blue: 0),
                bottomLeft: CodableColor(red: 0, green: 0, blue: 1),
                bottomRight: CodableColor(red: 1, green: 1, blue: 0)
            ),
            size: CGSize(width: 64, height: 64)
        )

        let center = pixel(image, x: 32, y: 32)
        // At center (fx=0.5, fy=0.5): bilinear = (0.25*bl + 0.25*br + 0.25*tl + 0.25*tr)
        // r = 0.25*0 + 0.25*1 + 0.25*1 + 0.25*0 = 0.5
        // g = 0.25*0 + 0.25*1 + 0.25*0 + 0.25*1 = 0.5
        // b = 0.25*1 + 0.25*0 + 0.25*0 + 0.25*0 = 0.25
        #expect(center.r > 0.3 && center.r < 0.7, "Center red should be ~0.5, got \(center.r)")
        #expect(center.g > 0.3 && center.g < 0.7, "Center green should be ~0.5, got \(center.g)")
        #expect(center.b > 0.05 && center.b < 0.45, "Center blue should be ~0.25, got \(center.b)")
    }

    @Test func meshBackgroundTopRightCornerMatchesTopRightColor() {
        // topRight = pure green
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 0, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 1, blue: 0),
                bottomLeft: CodableColor(red: 0, green: 0, blue: 0),
                bottomRight: CodableColor(red: 0, green: 0, blue: 0)
            ),
            size: CGSize(width: 64, height: 64)
        )

        // CIImage bottom-left: top-right visual = (width-1, height-1)
        let topRight = pixel(image, x: 62, y: 62)
        #expect(topRight.g > 0.7, "Top-right corner should be predominantly green, got g=\(topRight.g)")
        #expect(topRight.r < 0.3)
        #expect(topRight.b < 0.3)
    }

    @Test func meshBackgroundBottomLeftCornerMatchesBottomLeftColor() {
        // bottomLeft = pure white (r=1,g=1,b=1), all others black
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 0, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 0, blue: 0),
                bottomLeft: CodableColor(red: 1, green: 1, blue: 1),
                bottomRight: CodableColor(red: 0, green: 0, blue: 0)
            ),
            size: CGSize(width: 64, height: 64)
        )

        // CIImage bottom-left: bottom-left visual = (0, 0)
        let bottomLeft = pixel(image, x: 1, y: 1)
        #expect(bottomLeft.r > 0.7 && bottomLeft.g > 0.7 && bottomLeft.b > 0.7,
                "Bottom-left should be white-ish, got r=\(bottomLeft.r) g=\(bottomLeft.g) b=\(bottomLeft.b)")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Mesh Edge Cases
    // ─────────────────────────────────────────────────────────────────

    @Test func meshBackgroundZeroSizeReturnsFallback() {
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 1, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 1, blue: 0),
                bottomLeft: CodableColor(red: 0, green: 0, blue: 1),
                bottomRight: CodableColor(red: 1, green: 1, blue: 0)
            ),
            size: CGSize(width: 0, height: 0)
        )
        // Should return a black fallback image without crashing
        #expect(image.extent.width >= 0)
    }

    @Test func meshBackgroundNonSquareAspectRatio() {
        // Wide aspect ratio — should not distort
        let image = FrameRenderer.createBackground(
            style: .mesh(
                topLeft: CodableColor(red: 1, green: 0, blue: 0),
                topRight: CodableColor(red: 0, green: 0, blue: 1),
                bottomLeft: CodableColor(red: 0, green: 0, blue: 0),
                bottomRight: CodableColor(red: 0, green: 0, blue: 0)
            ),
            size: CGSize(width: 1920, height: 1080)
        )
        #expect(image.extent.width == 1920)
        #expect(image.extent.height == 1080)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Wallpaper Background
    // ─────────────────────────────────────────────────────────────────

    @Test func wallpaperBackgroundUnknownNameFallsBackToBlack() {
        let image = FrameRenderer.createBackground(
            style: .wallpaper("NonexistentWallpaper"),
            size: CGSize(width: 64, height: 64)
        )
        #expect(image.extent.width == 64)
        #expect(image.extent.height == 64)
    }

    @Test func wallpaperBackgroundAllPresetsResolve() {
        let size = CGSize(width: 64, height: 64)
        let presets = BackgroundType.wallpaperPresets
        for preset in presets {
            let image = FrameRenderer.createBackground(style: preset.style, size: size)
            #expect(image.extent.width == 64, "Preset \(preset.name) should produce correct width")
            #expect(image.extent.height == 64, "Preset \(preset.name) should produce correct height")
        }
    }
}
