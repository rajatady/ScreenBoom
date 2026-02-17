import Testing
import AVFoundation
import CoreImage
import AppKit
@testable import Screenboom

// MARK: - Export Pipeline End-to-End Tests
//
// These tests generate real video files, run the actual composition/export pipeline,
// and verify the output matches expectations. They catch regressions like:
// - Disabled segments appearing in export
// - Speed changes not applying
// - Duration mismatch between preview and export

struct ExportPipelineTests {

    // MARK: - Helpers

    /// Generate a silent solid-color video of known duration for testing.
    private static func generateTestVideo(duration: Double, size: CGSize = CGSize(width: 320, height: 240), fps: Int = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let pb = pixelBuffer else { continue }
            // Fill with solid color (no need for real content)
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                memset(base, 128, CVPixelBufferGetDataSize(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            adaptor.append(pb, withPresentationTime: pts)
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw NSError(domain: "ExportPipelineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate test video: \(writer.error?.localizedDescription ?? "unknown")"])
        }
        return url
    }

    /// Get the duration of a video file in seconds.
    private static func videoDuration(at url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    // MARK: - Composition Tests (fast, no disk export)

    @Test func compositionExcludesDisabledSegments() async throws {
        // 10-second video, split into two 5s segments, second one disabled
        let videoURL = try await Self.generateTestVideo(duration: 10.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let segments = [
            Segment(startTime: 0, endTime: 5, speed: 1.0, isEnabled: true),
            Segment(startTime: 5, endTime: 10, speed: 1.0, isEnabled: false)
        ]
        let enabledSegments = segments.filter(\.isEnabled)
        let composition = CompositionEngine.buildComposition(asset: asset, segments: enabledSegments)

        let compositionDuration = composition.duration.seconds
        // Only the first 5s segment is enabled → output should be ~5s
        #expect(abs(compositionDuration - 5.0) < 0.2, "Expected ~5s, got \(compositionDuration)s. Disabled segment was included.")
    }

    @Test func compositionAppliesSpeedChange() async throws {
        // 10-second video at 2x speed → should be ~5s output
        let videoURL = try await Self.generateTestVideo(duration: 10.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let segments = [
            Segment(startTime: 0, endTime: 10, speed: 2.0, isEnabled: true)
        ]
        let composition = CompositionEngine.buildComposition(asset: asset, segments: segments)

        let compositionDuration = composition.duration.seconds
        // 10s at 2x → ~5s output
        #expect(abs(compositionDuration - 5.0) < 0.2, "Expected ~5s at 2x speed, got \(compositionDuration)s. Speed not applied.")
    }

    @Test func compositionHandlesDisabledPlusSpeed() async throws {
        // 12-second video:
        //   [0-4s] enabled, 1x speed → 4s output
        //   [4-8s] disabled → 0s output
        //   [8-12s] enabled, 2x speed → 2s output
        // Expected total: 6s
        let videoURL = try await Self.generateTestVideo(duration: 12.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: false),
            Segment(startTime: 8, endTime: 12, speed: 2.0, isEnabled: true)
        ]
        let enabledSegments = segments.filter(\.isEnabled)
        let composition = CompositionEngine.buildComposition(asset: asset, segments: enabledSegments)

        let compositionDuration = composition.duration.seconds
        let expectedDuration = 4.0 + 2.0 // 4s at 1x + 4s at 2x = 6s
        #expect(abs(compositionDuration - expectedDuration) < 0.3, "Expected ~\(expectedDuration)s, got \(compositionDuration)s. Disabled/speed not correct.")
    }

    // MARK: - Full Export Tests (writes to disk, reads back)

    @Test func exportRespectsDisabledSegments() async throws {
        // 6-second video, first 3s enabled, last 3s disabled
        let videoURL = try await Self.generateTestVideo(duration: 6.0)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let sourceSize = CGSize(width: 320, height: 240)
        let segments = [
            Segment(startTime: 0, endTime: 3, speed: 1.0, isEnabled: true),
            Segment(startTime: 3, endTime: 6, speed: 1.0, isEnabled: false)
        ]
        let enabledSegments = segments.filter(\.isEnabled)
        let composition = CompositionEngine.buildComposition(asset: asset, segments: enabledSegments)
        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: sourceSize,
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                gradientColor1: .black, gradientColor2: .black,
                outputSize: sourceSize
            )
        )

        try await CompositionEngine.export(
            composition: composition,
            videoComposition: videoComp,
            outputSize: sourceSize,
            to: outputURL,
            progress: { _ in }
        )

        let exportedDuration = try await Self.videoDuration(at: outputURL)
        #expect(abs(exportedDuration - 3.0) < 0.3, "Exported video should be ~3s (disabled segment excluded), got \(exportedDuration)s")
    }

    @Test func exportRespectsSpeedChanges() async throws {
        // 8-second video at 4x speed → should be ~2s
        let videoURL = try await Self.generateTestVideo(duration: 8.0)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let sourceSize = CGSize(width: 320, height: 240)
        let segments = [
            Segment(startTime: 0, endTime: 8, speed: 4.0, isEnabled: true)
        ]
        let composition = CompositionEngine.buildComposition(asset: asset, segments: segments)
        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: sourceSize,
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                gradientColor1: .black, gradientColor2: .black,
                outputSize: sourceSize
            )
        )

        try await CompositionEngine.export(
            composition: composition,
            videoComposition: videoComp,
            outputSize: sourceSize,
            to: outputURL,
            progress: { _ in }
        )

        let exportedDuration = try await Self.videoDuration(at: outputURL)
        let expectedDuration = 2.0
        #expect(abs(exportedDuration - expectedDuration) < 0.3, "Exported video should be ~\(expectedDuration)s at 4x, got \(exportedDuration)s")
    }

    @Test func exportWithSolidBackgroundAndBrowserChrome() async throws {
        // Export with non-default background + frame style → valid MP4
        let videoURL = try await Self.generateTestVideo(duration: 4.0)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let sourceSize = CGSize(width: 320, height: 240)
        let segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true)
        ]
        let composition = CompositionEngine.buildComposition(asset: asset, segments: segments)
        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: sourceSize,
            settings: FrameRenderer.Settings(
                padding: 40, cornerRadius: 12, shadowRadius: 20, shadowOpacity: 0.4,
                backgroundStyle: .solid(CodableColor(red: 0.1, green: 0.1, blue: 0.2)),
                frameStyle: .browserChrome,
                outputSize: sourceSize
            )
        )

        try await CompositionEngine.export(
            composition: composition,
            videoComposition: videoComp,
            outputSize: sourceSize,
            to: outputURL,
            progress: { _ in }
        )

        let exportedDuration = try await Self.videoDuration(at: outputURL)
        #expect(abs(exportedDuration - 4.0) < 0.3, "Exported video should be ~4s, got \(exportedDuration)s")
    }

    @Test func exportCombinedDisabledAndSpeed() async throws {
        // The regression test: exactly the scenario that was broken.
        // 12-second video:
        //   [0-4s] enabled, 1x → 4s
        //   [4-8s] DISABLED → 0s
        //   [8-12s] enabled, 2x → 2s
        // Expected export: ~6s
        let videoURL = try await Self.generateTestVideo(duration: 12.0)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let sourceSize = CGSize(width: 320, height: 240)
        let segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 1.0, isEnabled: false),
            Segment(startTime: 8, endTime: 12, speed: 2.0, isEnabled: true)
        ]
        let enabledSegments = segments.filter(\.isEnabled)
        let composition = CompositionEngine.buildComposition(asset: asset, segments: enabledSegments)
        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: sourceSize,
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                gradientColor1: .black, gradientColor2: .black,
                outputSize: sourceSize
            )
        )

        try await CompositionEngine.export(
            composition: composition,
            videoComposition: videoComp,
            outputSize: sourceSize,
            to: outputURL,
            progress: { _ in }
        )

        let exportedDuration = try await Self.videoDuration(at: outputURL)
        let expectedDuration = 6.0
        #expect(abs(exportedDuration - expectedDuration) < 0.5, "Exported video should be ~\(expectedDuration)s (4s@1x + skip 4s + 4s@2x), got \(exportedDuration)s")
    }
}
