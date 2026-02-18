import Testing
import CoreImage
@testable import Screenboom

struct CursorOverlayEngineRenderTests {

    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    private func makeCursorImage() -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    private func makeSinglePixelCursor() -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

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

    private func makeState(
        settings: CursorSettings = CursorSettings(),
        smoothedPoints: [SmoothedCursorPoint] = [],
        clicks: [CursorClick] = [],
        zoomKeyframes: [ZoomKeyframe] = []
    ) -> CursorOverlayState {
        CursorOverlayState(
            smoothedPoints: smoothedPoints,
            clicks: clicks,
            cursorCIImage: makeCursorImage(),
            cursorHotspot: CGPoint(x: 4, y: 4),
            sourceSize: CGSize(width: 100, height: 50),
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: zoomKeyframes
        )
    }

    @Test func zoomCropRectReturnsNilWhenAutoZoomDisabledOrAtUnity() {
        var disabledSettings = CursorSettings()
        disabledSettings.autoZoomEnabled = false
        let disabledState = makeState(
            settings: disabledSettings,
            zoomKeyframes: [
                ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 50, y: 25), easingDuration: 0),
            ]
        )
        #expect(
            CursorOverlayEngine.zoomCropRect(
                in: disabledState,
                at: 0.0,
                sourceExtent: CGRect(x: 0, y: 0, width: 100, height: 50)
            ) == nil
        )

        var unitySettings = CursorSettings()
        unitySettings.autoZoomEnabled = true
        let unityState = makeState(
            settings: unitySettings,
            zoomKeyframes: [
                ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusPoint: CGPoint(x: 50, y: 25), easingDuration: 0),
            ]
        )
        #expect(
            CursorOverlayEngine.zoomCropRect(
                in: unityState,
                at: 0.0,
                sourceExtent: CGRect(x: 0, y: 0, width: 100, height: 50)
            ) == nil
        )
    }

    @Test func zoomCropRectClampsInsideSourceBoundsNearEdges() {
        var settings = CursorSettings()
        settings.autoZoomEnabled = true

        let state = makeState(
            settings: settings,
            zoomKeyframes: [
                ZoomKeyframe(timestamp: 0, zoomLevel: 2.0, focusPoint: CGPoint(x: 2, y: 2), easingDuration: 0),
            ]
        )

        let crop = CursorOverlayEngine.zoomCropRect(
            in: state,
            at: 0,
            sourceExtent: CGRect(x: 0, y: 0, width: 100, height: 50)
        )

        #expect(crop != nil)
        #expect(abs((crop?.width ?? 0) - 50.0) < 0.0001)
        #expect(abs((crop?.height ?? 0) - 25.0) < 0.0001)
        #expect(abs(crop?.minX ?? -1) < 0.0001)
        #expect(abs((crop?.minY ?? -1) - 25.0) < 0.0001)
    }

    @Test func cursorCompositeReturnsNilWhenCursorDisabled() {
        var settings = CursorSettings()
        settings.isEnabled = false
        settings.clickEffectEnabled = true

        let state = makeState(
            settings: settings,
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 20, y: 20),
            ],
            clicks: [
                CursorClick(timestamp: 0, x: 20, y: 20, button: .left),
            ]
        )

        let composite = CursorOverlayEngine.cursorComposite(
            in: state,
            at: 0.1,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )

        #expect(composite == nil)
    }

    @Test func cursorCompositeIncludesClickEffectsEvenWithoutMoveSamples() {
        var settings = CursorSettings()
        settings.isEnabled = true
        settings.clickEffectEnabled = true
        settings.clickEffectDuration = 0.5
        settings.clickEffectMaxRadius = 20

        let state = makeState(
            settings: settings,
            smoothedPoints: [],
            clicks: [
                CursorClick(timestamp: 0, x: 30, y: 20, button: .left),
            ]
        )

        let composite = CursorOverlayEngine.cursorComposite(
            in: state,
            at: 0.1,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )

        #expect(composite != nil)
    }

    @Test func remapForExportWithEmptyTableKeepsInteractionsButNoSmoothedSamples() {
        let state = makeState(
            settings: CursorSettings(),
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 0, y: 0),
                SmoothedCursorPoint(timestamp: 1, x: 10, y: 10),
            ],
            clicks: [
                CursorClick(timestamp: 0.5, x: 5, y: 5, button: .left),
            ],
            zoomKeyframes: [
                ZoomKeyframe(timestamp: 0.5, zoomLevel: 1.4, focusPoint: CGPoint(x: 20, y: 10), easingDuration: 0.3),
            ]
        )

        let remapped = CursorOverlayEngine.remapForExport(
            state: state,
            remapTable: TimeRemapTable(entries: [])
        )

        #expect(remapped.smoothedPoints.isEmpty)
        #expect(remapped.clicks.count == 1)
        #expect(abs(remapped.clicks[0].timestamp - 0.5) < 0.0001)
        #expect(remapped.zoomKeyframes.count == 1)
        #expect(abs(remapped.zoomKeyframes[0].timestamp - 0.5) < 0.0001)
    }

    @Test func cursorCompositePlacesCursorAtExpectedOutputPosition() {
        var settings = CursorSettings()
        settings.isEnabled = true
        settings.clickEffectEnabled = false

        let state = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0.0, x: 50, y: 25),
            ],
            clicks: [],
            cursorCIImage: makeSinglePixelCursor(),
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 100, height: 50),
            captureOrigin: .zero,
            settings: settings,
            zoomKeyframes: []
        )

        let composite = CursorOverlayEngine.cursorComposite(
            in: state,
            at: 0.0,
            recordingRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            outputSize: CGSize(width: 100, height: 50),
            zoomCropRect: nil
        )

        #expect(composite != nil)
        guard let composite else { return }

        // For 1x cursor at (50,25) top-left output coords:
        // CI coords become (x=50, y=24) due top-left -> bottom-left conversion.
        #expect(alphaAt(composite, x: 50, y: 24) > 0.95)
        #expect(alphaAt(composite, x: 10, y: 24) < 0.1)
    }
}
