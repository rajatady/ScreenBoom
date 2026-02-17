import Testing
import Foundation
import CoreImage
import AppKit
@testable import Screenboom

struct FrameRendererTests {

    // MARK: - createBackground

    @Test func solidBackgroundCreatesCorrectSize() {
        let size = CGSize(width: 1920, height: 1080)
        let style = BackgroundType.solid(CodableColor(red: 0.5, green: 0.5, blue: 0.5))
        let image = FrameRenderer.createBackground(style: style, size: size)
        #expect(image.extent.width == size.width)
        #expect(image.extent.height == size.height)
    }

    @Test func gradientBackgroundCreatesNonNilImage() {
        let size = CGSize(width: 1920, height: 1080)
        let style = BackgroundType.gradient(
            CodableColor(red: 0.1, green: 0.1, blue: 0.1),
            CodableColor(red: 0.9, green: 0.9, blue: 0.9)
        )
        let image = FrameRenderer.createBackground(style: style, size: size)
        #expect(image.extent.width == size.width)
        #expect(image.extent.height == size.height)
    }

    @Test func meshBackgroundCreatesCorrectSize() {
        let size = CGSize(width: 1920, height: 1080)
        let style = BackgroundType.mesh(
            topLeft: CodableColor(red: 1, green: 0, blue: 0),
            topRight: CodableColor(red: 0, green: 1, blue: 0),
            bottomLeft: CodableColor(red: 0, green: 0, blue: 1),
            bottomRight: CodableColor(red: 1, green: 1, blue: 0)
        )
        let image = FrameRenderer.createBackground(style: style, size: size)
        #expect(image.extent.width == size.width)
        #expect(image.extent.height == size.height)
    }

    @Test func wallpaperBackgroundResolves() {
        let size = CGSize(width: 1920, height: 1080)
        let style = BackgroundType.wallpaper("Sunset")
        let image = FrameRenderer.createBackground(style: style, size: size)
        #expect(image.extent.width == size.width)
        #expect(image.extent.height == size.height)
    }

    // MARK: - createFrameOverlay

    @Test func frameOverlayNoneReturnsNil() {
        let image = FrameRenderer.createFrameOverlay(
            style: .none,
            rect: CGRect(x: 100, y: 100, width: 1720, height: 880),
            chromeHeight: 0,
            cornerRadius: 16,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        #expect(image == nil)
    }

    @Test func frameOverlayBorderReturnsNonNil() {
        let image = FrameRenderer.createFrameOverlay(
            style: .border(width: 3, color: CodableColor(red: 1, green: 0, blue: 0)),
            rect: CGRect(x: 100, y: 100, width: 1720, height: 880),
            chromeHeight: 0,
            cornerRadius: 16,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        #expect(image != nil)
    }

    @Test func frameOverlayBrowserChromeReturnsNonNil() {
        let image = FrameRenderer.createFrameOverlay(
            style: .browserChrome,
            rect: CGRect(x: 100, y: 100, width: 1720, height: 840),
            chromeHeight: 40,
            cornerRadius: 16,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        #expect(image != nil)
    }

    // MARK: - calculateRecordingRect

    @Test func recordingRectWithChromeHeightReducesHeight() {
        let source = CGSize(width: 1920, height: 1080)
        let output = CGSize(width: 3840, height: 2160)

        let withoutChrome = FrameRenderer.calculateRecordingRect(
            sourceSize: source, outputSize: output, padding: 60, chromeHeight: 0
        )
        let withChrome = FrameRenderer.calculateRecordingRect(
            sourceSize: source, outputSize: output, padding: 60, chromeHeight: 40
        )

        // With chrome, the video rect should be shorter or positioned lower
        #expect(withChrome.height <= withoutChrome.height)
    }

    @Test func recordingRectWithZeroChromeUnchanged() {
        let source = CGSize(width: 1920, height: 1080)
        let output = CGSize(width: 3840, height: 2160)

        let rect = FrameRenderer.calculateRecordingRect(
            sourceSize: source, outputSize: output, padding: 60, chromeHeight: 0
        )

        // Should be centered with padding
        #expect(rect.origin.x >= 60)
        #expect(rect.width > 0)
        #expect(rect.height > 0)
    }
}
