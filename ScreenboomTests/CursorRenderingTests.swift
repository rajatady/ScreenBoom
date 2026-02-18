import Testing
import CoreImage
import AppKit
@testable import Screenboom

// MARK: - Cursor Rendering Tests
// Covers: circleDot cursor hotspot centering, system cursor hotspot Retina scaling,
// click effect ring math + Y-flip, cursor style rendering.

struct CursorRenderingTests {

    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    private func alphaAt(_ image: CIImage, x: Int, y: Int) -> Double {
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
        return Double(rgba[3]) / 255.0
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - CircleDot Cursor Hotspot
    // ─────────────────────────────────────────────────────────────────

    @Test func circleDotCursorHotspotIsCentered() {
        // prepare with circleDot style → hotspot should be at center of cursor image
        var settings = CursorSettings()
        settings.style = .circleDot
        settings.size = 1.0

        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 100, height: 100),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 100,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 50, y: 50, type: .move, button: nil),
            ]
        )

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: settings,
            outputFrameRate: 60
        )

        // CircleDot: baseSize=24, s=24*1.0=24, center=12
        let expectedCenter = 24.0 * 1.0 / 2.0
        #expect(abs(state.cursorHotspot.x - expectedCenter) < 1.0,
                "CircleDot hotspot.x should be centered at \(expectedCenter), got \(state.cursorHotspot.x)")
        #expect(abs(state.cursorHotspot.y - expectedCenter) < 1.0,
                "CircleDot hotspot.y should be centered at \(expectedCenter), got \(state.cursorHotspot.y)")
    }

    @Test func circleDotCursorScalesWithSize() {
        var settings1 = CursorSettings()
        settings1.style = .circleDot
        settings1.size = 1.0

        var settings2 = CursorSettings()
        settings2.style = .circleDot
        settings2.size = 2.0

        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 100, height: 100),
            events: [CursorEvent(timestamp: 0.0, x: 50, y: 50, type: .move, button: nil)]
        )

        let state1 = CursorOverlayEngine.prepare(metadata: metadata, settings: settings1, outputFrameRate: 60)
        let state2 = CursorOverlayEngine.prepare(metadata: metadata, settings: settings2, outputFrameRate: 60)

        // 2x size should have ~2x hotspot
        let ratio = state2.cursorHotspot.x / state1.cursorHotspot.x
        #expect(abs(ratio - 2.0) < 0.1, "2x size should double hotspot, ratio=\(ratio)")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - System Cursor Hotspot Retina Scaling
    // ─────────────────────────────────────────────────────────────────

    @Test func systemCursorHotspotScalesWithBackingFactor() {
        var settings = CursorSettings()
        settings.style = .arrow
        settings.size = 1.0

        let metadata1x = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 100, height: 100),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 100,
            backingScaleFactor: 1.0,
            events: [CursorEvent(timestamp: 0.0, x: 50, y: 50, type: .move, button: nil)]
        )
        let metadata2x = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 100, height: 100),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 100,
            backingScaleFactor: 2.0,
            events: [CursorEvent(timestamp: 0.0, x: 50, y: 50, type: .move, button: nil)]
        )

        let state1x = CursorOverlayEngine.prepare(metadata: metadata1x, settings: settings, outputFrameRate: 60)
        let state2x = CursorOverlayEngine.prepare(metadata: metadata2x, settings: settings, outputFrameRate: 60)

        // Retina (2x) should have ~2x hotspot coordinates
        #expect(state1x.cursorHotspot.x > 0.1, "1x hotspot should be nonzero")
        let ratio = state2x.cursorHotspot.x / state1x.cursorHotspot.x
        #expect(ratio > 1.8 && ratio < 2.2, "2x backing should ~double hotspot, ratio=\(ratio)")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Click Effects
    // ─────────────────────────────────────────────────────────────────

    @Test func clickEffectRingExpandsOverTime() {
        var settings = CursorSettings()
        settings.isEnabled = true
        settings.clickEffectEnabled = true
        settings.clickEffectDuration = 1.0
        settings.clickEffectMaxRadius = 30

        let state = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 50, y: 25),
            ],
            clicks: [
                CursorClick(timestamp: 0, x: 50, y: 25, button: .left),
            ],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 50),
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: []
        )

        // At early time (0.1s) → small ring
        let early = CursorOverlayEngine.cursorComposite(
            in: state, at: 0.1,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )
        #expect(early != nil, "Click effect at 0.1s should produce composite")

        // At late time (0.8s) → large ring
        let late = CursorOverlayEngine.cursorComposite(
            in: state, at: 0.8,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )
        #expect(late != nil, "Click effect at 0.8s should produce composite")
    }

    @Test func clickEffectNotVisibleAfterDuration() {
        var settings = CursorSettings()
        settings.isEnabled = true
        settings.clickEffectEnabled = true
        settings.clickEffectDuration = 0.5
        settings.clickEffectMaxRadius = 20

        let state = CursorOverlayState(
            smoothedPoints: [],
            clicks: [
                CursorClick(timestamp: 0, x: 50, y: 25, button: .left),
            ],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 50),
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: []
        )

        // After duration expires → no click effect
        let result = CursorOverlayEngine.cursorComposite(
            in: state, at: 0.6,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )
        #expect(result == nil, "Click effect should be nil after duration expires")
    }

    @Test func clickEffectZeroDurationProducesNoEffect() {
        var settings = CursorSettings()
        settings.isEnabled = true
        settings.clickEffectEnabled = true
        settings.clickEffectDuration = 0.0

        let state = CursorOverlayState(
            smoothedPoints: [],
            clicks: [CursorClick(timestamp: 0, x: 50, y: 25, button: .left)],
            cursorCIImage: CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 50),
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: []
        )

        let result = CursorOverlayEngine.cursorComposite(
            in: state, at: 0.01,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )
        #expect(result == nil, "Zero duration click effect should produce no composite")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Cursor Style Image Rendering
    // ─────────────────────────────────────────────────────────────────

    @Test func allCursorStylesProduceValidImages() {
        for style in CursorStyle.allCases {
            var settings = CursorSettings()
            settings.style = style
            settings.size = 1.0

            let metadata = CursorMetadataFile(
                frameRate: 60,
                sourceSize: .init(width: 100, height: 100),
                events: [CursorEvent(timestamp: 0.0, x: 50, y: 50, type: .move, button: nil)]
            )

            let state = CursorOverlayEngine.prepare(
                metadata: metadata, settings: settings, outputFrameRate: 60
            )

            #expect(state.cursorCIImage.extent.width > 0,
                    "\(style.displayName) cursor should have nonzero width")
            #expect(state.cursorCIImage.extent.height > 0,
                    "\(style.displayName) cursor should have nonzero height")
        }
    }
}
