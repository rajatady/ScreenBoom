import Testing
import CoreImage
@testable import Screenboom

struct CursorOverlayEngineBehaviorTests {

    @Test func cursorStyleDisplayNameRoundTripAndFallback() {
        for style in CursorStyle.allCases {
            let parsed = CursorStyle.fromDisplayName(style.displayName)
            #expect(parsed == style)
        }
        #expect(CursorStyle.fromDisplayName("Unknown") == .arrow)
    }

    @Test func timeRemapTableInterpolatesAndClampsEndpoints() {
        let table = TimeRemapTable(entries: [
            TimeRemapEntry(compositionTime: 0, sourceTime: 0),
            TimeRemapEntry(compositionTime: 1, sourceTime: 2),
            TimeRemapEntry(compositionTime: 2, sourceTime: 4),
        ])

        #expect(abs(table.sourceTime(forCompositionTime: -1) - 0) < 0.0001)
        #expect(abs(table.sourceTime(forCompositionTime: 0.5) - 1) < 0.0001)
        #expect(abs(table.sourceTime(forCompositionTime: 1.5) - 3) < 0.0001)
        #expect(abs(table.sourceTime(forCompositionTime: 3) - 4) < 0.0001)
    }

    @Test func extractInteractionsConvertsCoordinatesUsingCaptureOriginAndDisplayHeight() {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 100, height: 50),
            captureOrigin: .init(x: 10, y: 20),
            displayHeight: 200,
            backingScaleFactor: 2,
            events: [
                CursorEvent(timestamp: 1.0, x: 30, y: 150, type: .click, button: .left),
                CursorEvent(timestamp: 2.0, x: 40, y: 140, type: .keyDown, button: nil),
            ]
        )

        let extracted = CursorOverlayEngine.extractInteractions(from: metadata)

        #expect(extracted.clicks.count == 1)
        #expect(abs(extracted.clicks[0].x - 20) < 0.0001)
        #expect(abs(extracted.clicks[0].y - 30) < 0.0001)

        #expect(extracted.keyInteractions.count == 1)
        #expect(abs(extracted.keyInteractions[0].x - 30) < 0.0001)
        #expect(abs(extracted.keyInteractions[0].y - 40) < 0.0001)

        #expect(extracted.sourceSize == CGSize(width: 100, height: 50))
    }

    @Test func extractInteractionsUsesFallbackDisplayHeightWhenMissing() {
        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 100, height: 50),
            captureOrigin: .init(x: 10, y: 20),
            displayHeight: nil,
            backingScaleFactor: 1,
            events: [
                CursorEvent(timestamp: 1.0, x: 30, y: 40, type: .click, button: .left),
                CursorEvent(timestamp: 2.0, x: 40, y: 35, type: .keyDown, button: nil),
            ]
        )

        let extracted = CursorOverlayEngine.extractInteractions(from: metadata)

        // fallback displayHeight = sourceHeight + originY = 70
        #expect(extracted.clicks.count == 1)
        #expect(abs(extracted.clicks[0].x - 20) < 0.0001)
        #expect(abs(extracted.clicks[0].y - 10) < 0.0001) // 70 - 40 - 20

        #expect(extracted.keyInteractions.count == 1)
        #expect(abs(extracted.keyInteractions[0].x - 30) < 0.0001)
        #expect(abs(extracted.keyInteractions[0].y - 15) < 0.0001) // 70 - 35 - 20
    }

    @Test func generateZoomRegionsClustersAndClampsFocus() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        let clicks = [
            CursorClick(timestamp: 1.0, x: 40, y: 60, button: .left),
            CursorClick(timestamp: 1.2, x: 50, y: 70, button: .left),
            CursorClick(timestamp: 1.4, x: 60, y: 80, button: .left),
            CursorClick(timestamp: 6.0, x: 1860, y: 1020, button: .left),
            CursorClick(timestamp: 6.2, x: 1840, y: 1000, button: .left),
        ]

        let regions = CursorOverlayEngine.generateZoomRegions(
            clicks: clicks,
            keyInteractions: [],
            sensitivity: .balanced,
            zoomLevel: 1.5,
            sourceSize: sourceSize
        )

        #expect(regions.count == 2)

        // At 1.5x zoom, focus must stay inside [640...1280] x [360...720]
        for region in regions {
            #expect(region.focusX >= 640 && region.focusX <= 1280)
            #expect(region.focusY >= 360 && region.focusY <= 720)
            #expect(region.startTime < region.endTime)
        }
    }

    @Test func zoomKeyframesUseHoldAndTransitionTiming() {
        let regions = [
            ZoomRegion(startTime: 2.0, endTime: 5.0, zoomLevel: 1.6, focusX: 500, focusY: 300),
        ]

        let keyframes = CursorOverlayEngine.zoomKeyframes(
            from: regions,
            sensitivity: .balanced,
            sourceSize: CGSize(width: 1000, height: 600)
        )

        #expect(keyframes.count == 5)
        #expect(abs(keyframes[0].timestamp - 0.0) < 0.0001)
        #expect(abs(keyframes[0].zoomLevel - 1.0) < 0.0001)

        // hold at 1.0 until start - zoomInDuration(0.5)
        #expect(abs(keyframes[1].timestamp - 1.5) < 0.0001)
        #expect(abs(keyframes[1].zoomLevel - 1.0) < 0.0001)

        #expect(abs(keyframes[2].timestamp - 2.0) < 0.0001)
        #expect(abs(keyframes[2].zoomLevel - 1.6) < 0.0001)
        #expect(abs(keyframes[2].easingDuration - 0.5) < 0.0001)

        #expect(abs(keyframes[3].timestamp - 4.2) < 0.0001) // end - zoomOutDuration(0.8)
        #expect(abs(keyframes[4].timestamp - 5.0) < 0.0001)
        #expect(abs(keyframes[4].zoomLevel - 1.0) < 0.0001)
    }

    @Test func zoomKeyframesIgnoreDisabledRegions() {
        let regions = [
            ZoomRegion(startTime: 1.0, endTime: 3.0, zoomLevel: 1.8, focusX: 400, focusY: 250, isEnabled: true),
            ZoomRegion(startTime: 5.0, endTime: 6.0, zoomLevel: 3.0, focusX: 800, focusY: 450, isEnabled: false),
        ]

        let keyframes = CursorOverlayEngine.zoomKeyframes(
            from: regions,
            sensitivity: .balanced,
            sourceSize: CGSize(width: 1200, height: 700)
        )

        #expect(!keyframes.isEmpty)
        #expect(!keyframes.contains(where: { abs($0.zoomLevel - 3.0) < 0.0001 }))
        for i in 1..<keyframes.count {
            #expect(keyframes[i].timestamp >= keyframes[i - 1].timestamp)
        }
    }

    @Test func generateZoomRegionsSupportsKeyboardOnlyInteractions() {
        let keyInteractions: [(timestamp: Double, x: Double, y: Double)] = [
            (1.0, 200, 120),
            (1.2, 220, 140),
            (1.4, 240, 160),
        ]

        let regions = CursorOverlayEngine.generateZoomRegions(
            clicks: [],
            keyInteractions: keyInteractions,
            sensitivity: .dramatic,
            zoomLevel: 2.0,
            sourceSize: CGSize(width: 1280, height: 720)
        )

        #expect(regions.count == 1)
        #expect(regions[0].startTime <= 1.0)
        #expect(regions[0].endTime >= 1.4)
    }

    @Test func prepareMapsClicksAndBuildsAutoZoomKeyframes() {
        var settings = CursorSettings()
        settings.autoZoomEnabled = true

        let metadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 200, height: 100),
            captureOrigin: .init(x: 10, y: 20),
            displayHeight: 300,
            backingScaleFactor: 2,
            events: [
                CursorEvent(timestamp: 0.0, x: 20, y: 260, type: .move, button: nil),
                CursorEvent(timestamp: 1.0, x: 30, y: 250, type: .click, button: .left),
                CursorEvent(timestamp: 2.0, x: 50, y: 240, type: .move, button: nil),
            ]
        )

        let regions = [
            ZoomRegion(startTime: 1.0, endTime: 2.0, zoomLevel: 1.4, focusX: 100, focusY: 60),
        ]

        let state = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: settings,
            outputFrameRate: 10,
            zoomRegions: regions
        )

        #expect(state.captureOrigin == CGPoint(x: 10, y: 20))
        #expect(state.sourceSize == CGSize(width: 200, height: 100))

        #expect(state.clicks.count == 1)
        #expect(abs(state.clicks[0].x - 20) < 0.0001)
        #expect(abs(state.clicks[0].y - 30) < 0.0001)

        // 2s sampled at 10 fps should produce about 20-21 points depending on floating-step accumulation.
        #expect(state.smoothedPoints.count >= 20 && state.smoothedPoints.count <= 21)
        #expect(abs(state.smoothedPoints.first?.timestamp ?? -1) < 0.0001)
        #expect(abs((state.smoothedPoints.last?.timestamp ?? -1) - 2.0) < 0.11)
        #expect(!state.zoomKeyframes.isEmpty)
    }

    @Test func remapForExportDropsInteractionsOutsideEnabledRanges() {
        let cursorImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let state = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0, x: 0, y: 0),
                SmoothedCursorPoint(timestamp: 2, x: 20, y: 20),
                SmoothedCursorPoint(timestamp: 4, x: 40, y: 40),
                SmoothedCursorPoint(timestamp: 8, x: 80, y: 80),
                SmoothedCursorPoint(timestamp: 12, x: 120, y: 120),
            ],
            clicks: [
                CursorClick(timestamp: 2, x: 20, y: 20, button: .left),
                CursorClick(timestamp: 6, x: 60, y: 60, button: .left), // disabled-gap click
            ],
            cursorCIImage: cursorImage,
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 1920, height: 1080),
            captureOrigin: .zero,
            settings: CursorSettings(),
            zoomKeyframes: [
                ZoomKeyframe(timestamp: 2, zoomLevel: 1.3, focusPoint: CGPoint(x: 500, y: 300), easingDuration: 0.5),
                ZoomKeyframe(timestamp: 6, zoomLevel: 1.0, focusPoint: CGPoint(x: 960, y: 540), easingDuration: 0.5),
            ]
        )

        let table = TimeRemapTable(entries: [
            TimeRemapEntry(compositionTime: 0, sourceTime: 0),
            TimeRemapEntry(compositionTime: 1, sourceTime: 1),
            TimeRemapEntry(compositionTime: 2, sourceTime: 2),
            TimeRemapEntry(compositionTime: 3, sourceTime: 3),
            TimeRemapEntry(compositionTime: 4, sourceTime: 4),
            TimeRemapEntry(compositionTime: 4.001, sourceTime: 8),
            TimeRemapEntry(compositionTime: 5, sourceTime: 9),
            TimeRemapEntry(compositionTime: 6, sourceTime: 10),
            TimeRemapEntry(compositionTime: 7, sourceTime: 11),
            TimeRemapEntry(compositionTime: 8, sourceTime: 12),
        ])

        let remapped = CursorOverlayEngine.remapForExport(state: state, remapTable: table)

        #expect(remapped.clicks.count == 1)
        #expect(abs(remapped.clicks[0].timestamp - 2.0) < 0.01)

        // source jump should trigger inserted cursor bridges
        #expect(remapped.smoothedPoints.count > table.entries.count)

        // keyframe at source=6 should be dropped (outside enabled ranges)
        #expect(remapped.zoomKeyframes.count == 1)
        #expect(abs(remapped.zoomKeyframes[0].timestamp - 2.0) < 0.01)
    }

    @Test func prepareScalesCursorHotspotByBackingScaleFactor() {
        var settings = CursorSettings()
        settings.style = .pointer
        settings.size = 1.0

        let baseMetadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 400, height: 300),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 300,
            backingScaleFactor: 1.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 50, y: 250, type: .move, button: nil),
            ]
        )

        let retinaMetadata = CursorMetadataFile(
            frameRate: 60,
            sourceSize: .init(width: 400, height: 300),
            captureOrigin: .init(x: 0, y: 0),
            displayHeight: 300,
            backingScaleFactor: 2.0,
            events: [
                CursorEvent(timestamp: 0.0, x: 50, y: 250, type: .move, button: nil),
            ]
        )

        let oneX = CursorOverlayEngine.prepare(
            metadata: baseMetadata,
            settings: settings,
            outputFrameRate: 60
        )
        let twoX = CursorOverlayEngine.prepare(
            metadata: retinaMetadata,
            settings: settings,
            outputFrameRate: 60
        )

        #expect(oneX.cursorHotspot.x > 0.1)
        let ratio = twoX.cursorHotspot.x / oneX.cursorHotspot.x
        #expect(ratio > 1.8 && ratio < 2.2)
    }
}
