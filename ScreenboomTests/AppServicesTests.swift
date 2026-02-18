import Testing
import Foundation
import AVFoundation
import CoreImage
@testable import Screenboom

@MainActor
struct AppServicesTests {
    private func makeTempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("screenboom-test-\(UUID().uuidString).\(ext)")
    }

    private func generateVideo(duration: Double, size: CGSize = CGSize(width: 160, height: 90), fps: Int = 24) async throws -> URL {
        let url = makeTempURL(ext: "mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let frameCount = max(1, Int(duration * Double(fps)))
        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                nil,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            )
            guard let pb = pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                memset(base, 120, CVPixelBufferGetDataSize(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw NSError(domain: "AppServicesTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to synthesize fixture video"])
        }
        return url
    }

    private func makeSavedState() -> SavedState {
        SavedState(
            sourceURLBookmark: nil,
            sourceURLPath: "/tmp/input.mp4",
            splitPoints: [1.2, 3.4],
            segmentStates: [SavedState.SavedSegment(startTime: 0, endTime: 5, speed: 1.0, isEnabled: true)],
            gradientColor1: [0.1, 0.2, 0.3],
            gradientColor2: [0.2, 0.3, 0.4],
            padding: 40,
            cornerRadius: 12,
            shadowRadius: 20,
            shadowOpacity: 0.4,
            outputWidth: 1920,
            outputHeight: 1080,
            playheadTime: 2.5,
            showThumbnails: true,
            backgroundStyleJSON: nil,
            frameStyleJSON: nil,
            cursorEnabled: true,
            cursorStyle: "arrow",
            cursorSize: 1.2,
            clickEffectEnabled: true,
            clickEffectColor: [1, 0, 0, 1],
            clickEffectMaxRadius: 40,
            clickEffectDuration: 0.5,
            autoZoomEnabled: true,
            autoZoomLevel: 1.3,
            autoZoomSensitivity: "balanced",
            zoomRegions: nil
        )
    }

    @Test func fileProjectStateStoreRoundTripsSavedState() throws {
        let store = FileProjectStateStore()
        let fileURL = makeTempURL(ext: "json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let state = makeSavedState()

        store.saveState(state, to: fileURL)
        let loaded = store.loadState(from: fileURL)

        #expect(loaded != nil)
        #expect(loaded?.splitPoints == [1.2, 3.4])
        #expect(loaded?.outputWidth == 1920)
        #expect(loaded?.cursorStyle == "arrow")
    }

    @Test func compositionExportServiceReturnsEarlyWhenNoSegmentsEnabled() async throws {
        let service = CompositionExportService()
        let sourceURL = try await generateVideo(duration: 1.0)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let outputURL = makeTempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var progressValues: [Double] = []
        try await service.export(
            asset: AVURLAsset(url: sourceURL),
            enabledSegments: [],
            sourceSize: CGSize(width: 160, height: 90),
            exportSettings: FrameRenderer.Settings(
                padding: 0,
                cornerRadius: 0,
                shadowRadius: 0,
                shadowOpacity: 0,
                backgroundStyle: .defaultStyle,
                frameStyle: .none,
                outputSize: CGSize(width: 160, height: 90)
            ),
            cursorOverlayState: nil,
            outputURL: outputURL
        ) { value in
            progressValues.append(value)
        }

        #expect(progressValues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test func compositionExportServiceExportsWithCursorRemapPath() async throws {
        let service = CompositionExportService()
        let sourceURL = try await generateVideo(duration: 1.5)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let outputURL = makeTempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let cursorImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let cursorState = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0.0, x: 20, y: 20),
                SmoothedCursorPoint(timestamp: 1.0, x: 120, y: 70),
            ],
            clicks: [
                CursorClick(timestamp: 0.7, x: 70, y: 40, button: .left),
            ],
            cursorCIImage: cursorImage,
            cursorHotspot: .zero,
            sourceSize: CGSize(width: 160, height: 90),
            captureOrigin: .zero,
            settings: CursorSettings(),
            zoomKeyframes: []
        )
        let segments = [
            Segment(startTime: 0.0, endTime: 1.5, speed: 1.0, isEnabled: true),
        ]

        var progressValues: [Double] = []
        try await service.export(
            asset: AVURLAsset(url: sourceURL),
            enabledSegments: segments,
            sourceSize: CGSize(width: 160, height: 90),
            exportSettings: FrameRenderer.Settings(
                padding: 0,
                cornerRadius: 0,
                shadowRadius: 0,
                shadowOpacity: 0,
                backgroundStyle: .defaultStyle,
                frameStyle: .none,
                outputSize: CGSize(width: 160, height: 90)
            ),
            cursorOverlayState: cursorState,
            outputURL: outputURL
        ) { value in
            progressValues.append(value)
        }

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(!progressValues.isEmpty)
        #expect(progressValues.last ?? 0 > 0.9)
    }
}
