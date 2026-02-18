import Testing
import CoreImage
@testable import Screenboom

struct FrameRendererDeterministicTests {

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

    @Test func pointScaleTracksOutputHeightRelativeTo1080p() {
        #expect(abs(FrameRenderer.pointScale(for: CGSize(width: 1920, height: 1080)) - 1.0) < 0.0001)
        #expect(abs(FrameRenderer.pointScale(for: CGSize(width: 3840, height: 2160)) - 2.0) < 0.0001)
        #expect(abs(FrameRenderer.pointScale(for: CGSize(width: 1280, height: 720)) - (2.0 / 3.0)) < 0.0001)
    }

    @Test func calculateRecordingRectFallsBackWhenPaddingConsumesCanvas() {
        let rect = FrameRenderer.calculateRecordingRect(
            sourceSize: CGSize(width: 1920, height: 1080),
            outputSize: CGSize(width: 200, height: 100),
            padding: 200,
            chromeHeight: 0
        )
        #expect(abs(rect.minX - 0.0) < 0.0001)
        #expect(abs(rect.minY - 0.0) < 0.0001)
        #expect(abs(rect.width - 200.0) < 0.0001)
        #expect(abs(rect.height - 100.0) < 0.0001)
    }

    @Test func solidBackgroundRendersExpectedCenterColor() {
        let image = FrameRenderer.createBackground(
            style: .solid(CodableColor(red: 0.2, green: 0.4, blue: 0.6)),
            size: CGSize(width: 64, height: 64)
        )
        let c = pixel(image, x: 32, y: 32)
        #expect(abs(c.r - 0.2) < 0.03)
        #expect(abs(c.g - 0.4) < 0.03)
        #expect(abs(c.b - 0.6) < 0.03)
        #expect(c.a > 0.95)
    }

    @Test func gradientBackgroundVariesAcrossDiagonal() {
        let image = FrameRenderer.createBackground(
            style: .gradient(
                CodableColor(red: 0.0, green: 0.0, blue: 0.0),
                CodableColor(red: 1.0, green: 1.0, blue: 1.0)
            ),
            size: CGSize(width: 64, height: 64)
        )
        let topLeft = pixel(image, x: 2, y: 61)
        let bottomRight = pixel(image, x: 61, y: 2)

        #expect(bottomRight.r > topLeft.r + 0.2)
        #expect(bottomRight.g > topLeft.g + 0.2)
        #expect(bottomRight.b > topLeft.b + 0.2)
    }

    @Test func borderOverlayIsOpaqueOnEdgeAndTransparentInside() {
        let overlay = FrameRenderer.createFrameOverlay(
            style: .border(width: 4, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
            rect: CGRect(x: 10, y: 10, width: 44, height: 44),
            chromeHeight: 0,
            cornerRadius: 8,
            outputSize: CGSize(width: 64, height: 64)
        )
        #expect(overlay != nil)
        guard let overlay else { return }

        let outside = pixel(overlay, x: 2, y: 2)
        let edge = pixel(overlay, x: 10, y: 32)
        let interior = pixel(overlay, x: 32, y: 32)

        #expect(outside.a < 0.05)
        #expect(edge.a > 0.2)
        #expect(interior.a < 0.1)
    }
}
