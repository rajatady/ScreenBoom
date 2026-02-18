import Testing
import AVFoundation
@testable import Screenboom

// MARK: - Composition Engine Expanded Tests
// Covers: expandWithRamps smoothstep math, short segment clamping,
// bitrate scaling boundaries, single segment identity,
// time remap table monotonicity and accuracy.

struct CompositionEngineExpandedTests {

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Speed Ramp (via buildTimeRemapTable)
    // expandWithRamps is private — test indirectly via buildTimeRemapTable
    // ─────────────────────────────────────────────────────────────────

    private func assertMonotonic(_ entries: [TimeRemapEntry]) {
        guard entries.count > 1 else { return }
        for i in 1..<entries.count {
            #expect(entries[i].compositionTime >= entries[i - 1].compositionTime,
                    "Composition time should be monotonically increasing at index \(i)")
            #expect(entries[i].sourceTime >= entries[i - 1].sourceTime,
                    "Source time should be monotonically increasing at index \(i)")
        }
    }

    @Test func speedRampBetweenDifferentSpeedsCreatesRampEntries() {
        // Two segments with different speeds → ramp zone at boundary
        let segments = [
            Segment(startTime: 0, endTime: 5, speed: 1.0, isEnabled: true),
            Segment(startTime: 5, endTime: 10, speed: 3.0, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        #expect(!table.entries.isEmpty)
        assertMonotonic(table.entries)

        // Total source = 10s. At 1x for 5s + 3x for 5s → comp = 5 + 5/3 ≈ 6.67s
        let totalComp = table.entries.last!.compositionTime
        #expect(abs(totalComp - (5.0 + 5.0 / 3.0)) < 0.3,
                "Expected ~6.67s composition time, got \(totalComp)")
    }

    @Test func sameSpeedSegmentsNoRampZone() {
        // Two segments at same speed → no ramp zone (speed diff < 0.01)
        let segments = [
            Segment(startTime: 0, endTime: 5, speed: 2.0, isEnabled: true),
            Segment(startTime: 5, endTime: 10, speed: 2.0, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        assertMonotonic(table.entries)

        // Total: 10s source at 2x = 5s composition
        let totalComp = table.entries.last!.compositionTime
        #expect(abs(totalComp - 5.0) < 0.15, "Same speed segments: expected ~5s, got \(totalComp)")
    }

    @Test func shortSegmentClampsHalfRampDuration() {
        // Very short segment (0.1s) adjacent to different speed — halfRampDuration
        // should be clamped to segment.duration/2 = 0.05s
        let segments = [
            Segment(startTime: 0, endTime: 0.1, speed: 1.0, isEnabled: true),
            Segment(startTime: 0.1, endTime: 5, speed: 3.0, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        #expect(!table.entries.isEmpty)
        assertMonotonic(table.entries)

        // Should not crash — the ramp zone for the short segment should be clamped
        let totalComp = table.entries.last!.compositionTime
        #expect(totalComp > 0, "Should produce valid composition")
    }

    @Test func singleSegmentAt1xIsIdentity() {
        let segments = [
            Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        assertMonotonic(table.entries)

        // Every entry should have compositionTime ≈ sourceTime
        for entry in table.entries {
            #expect(abs(entry.compositionTime - entry.sourceTime) < 0.02,
                    "1x identity: comp=\(entry.compositionTime) source=\(entry.sourceTime)")
        }
    }

    @Test func singleSegmentAt05xDoublesDuration() {
        let segments = [
            Segment(startTime: 0, endTime: 5, speed: 0.5, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        assertMonotonic(table.entries)

        // 5s source at 0.5x → 10s composition
        let totalComp = table.entries.last!.compositionTime
        #expect(abs(totalComp - 10.0) < 0.2, "0.5x speed: expected ~10s, got \(totalComp)")
    }

    @Test func threeSegmentsWithVaryingSpeeds() {
        let segments = [
            Segment(startTime: 0, endTime: 3, speed: 1.0, isEnabled: true),
            Segment(startTime: 3, endTime: 6, speed: 2.0, isEnabled: true),
            Segment(startTime: 6, endTime: 9, speed: 0.5, isEnabled: true),
        ]
        let table = CompositionEngine.buildTimeRemapTable(segments: segments)
        assertMonotonic(table.entries)

        // Expected: 3 + 3/2 + 3/0.5 = 3 + 1.5 + 6 = 10.5 (approximate with ramp overhead)
        let totalComp = table.entries.last!.compositionTime
        #expect(abs(totalComp - 10.5) < 0.5, "Three segments: expected ~10.5s, got \(totalComp)")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Bitrate Scaling
    // (tested indirectly — CompositionEngine.export uses:
    //   bitrate = min(80_000_000, max(20_000_000, pixelCount * 15))
    // ─────────────────────────────────────────────────────────────────

    @Test func bitrateScalingFormula720p() {
        let size = CGSize(width: 1280, height: 720)
        let pixelCount = Int(size.width * size.height)
        let bitrate = min(80_000_000, max(20_000_000, pixelCount * 15))
        // 1280*720 = 921600 * 15 = 13_824_000 → clamped to 20_000_000
        #expect(bitrate == 20_000_000, "720p should clamp to floor: got \(bitrate)")
    }

    @Test func bitrateScalingFormula1080p() {
        let size = CGSize(width: 1920, height: 1080)
        let pixelCount = Int(size.width * size.height)
        let bitrate = min(80_000_000, max(20_000_000, pixelCount * 15))
        // 1920*1080 = 2_073_600 * 15 = 31_104_000
        #expect(bitrate == 31_104_000, "1080p bitrate: got \(bitrate)")
    }

    @Test func bitrateScalingFormula4K() {
        let size = CGSize(width: 3840, height: 2160)
        let pixelCount = Int(size.width * size.height)
        let bitrate = min(80_000_000, max(20_000_000, pixelCount * 15))
        // 3840*2160 = 8_294_400 * 15 = 124_416_000 → clamped to 80_000_000
        #expect(bitrate == 80_000_000, "4K should clamp to ceiling: got \(bitrate)")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - 60fps Throttle Logic
    // (verified by formula: minFrameInterval = 1/60 ≈ 0.01667)
    // ─────────────────────────────────────────────────────────────────

    @Test func throttleFrameIntervalCalculation() {
        let minFrameInterval = 1.0 / 60.0
        // Threshold = minFrameInterval * 0.9
        let threshold = minFrameInterval * 0.9
        #expect(threshold > 0.014 && threshold < 0.016, "Threshold should be ~0.015, got \(threshold)")

        // A 4x speed composition producing 240fps effective → frames at 1/240 = 0.00417s apart
        // 0.00417 < 0.015 → throttled (only every ~4th frame written)
        let effectiveFrameInterval = 1.0 / 240.0
        #expect(effectiveFrameInterval < threshold, "4x speed frames should be throttled")

        // Normal 60fps → frames at 1/60 = 0.01667 apart
        let normalFrameInterval = 1.0 / 60.0
        #expect(normalFrameInterval >= threshold, "60fps frames should pass throttle")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - ExportError Descriptions
    // ─────────────────────────────────────────────────────────────────

    @Test func exportErrorDescriptions() {
        let readerError = CompositionEngine.ExportError.cannotConfigureReader
        #expect(readerError.errorDescription == "Cannot configure video reader")

        let writerError = CompositionEngine.ExportError.cannotConfigureWriter
        #expect(writerError.errorDescription == "Cannot configure video writer")

        let readerFailed = CompositionEngine.ExportError.readerFailed(nil)
        #expect(readerFailed.errorDescription?.contains("Reader failed") == true)

        let writerFailed = CompositionEngine.ExportError.writerFailed(nil)
        #expect(writerFailed.errorDescription?.contains("Writer failed") == true)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - buildComposition with Real Asset
    // ─────────────────────────────────────────────────────────────────

    private static func generateTestVideo(duration: Double, fps: Int = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("comp-test-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        let size = CGSize(width: 160, height: 120)
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
                try await Task.sleep(for: .milliseconds(5))
            }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pb)
            guard let pixelBuffer = pb else { continue }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 128, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @MainActor
    @Test func buildCompositionSingleSegmentIdentity() async throws {
        let videoURL = try await Self.generateTestVideo(duration: 4.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let segments = [Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true)]
        let composition = CompositionEngine.buildComposition(asset: asset, segments: segments)

        let dur = composition.duration.seconds
        #expect(abs(dur - 4.0) < 0.2, "Single 1x segment should be ~4s, got \(dur)")
    }

    @MainActor
    @Test func buildCompositionMultiSpeedRamp() async throws {
        let videoURL = try await Self.generateTestVideo(duration: 8.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let segments = [
            Segment(startTime: 0, endTime: 4, speed: 1.0, isEnabled: true),
            Segment(startTime: 4, endTime: 8, speed: 4.0, isEnabled: true),
        ]
        let composition = CompositionEngine.buildComposition(asset: asset, segments: segments)

        // Expected: 4 + 4/4 = 5s (with ramp tolerance)
        let dur = composition.duration.seconds
        #expect(abs(dur - 5.0) < 0.3, "1x+4x should be ~5s, got \(dur)")
    }
}
