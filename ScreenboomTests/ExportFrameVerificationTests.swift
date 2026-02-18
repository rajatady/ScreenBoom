import Testing
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import Screenboom

// MARK: - Export Frame Verification Tests
//
// These tests export real video through the full pipeline (CompositionEngine + FrameRenderer),
// then READ BACK frames from the output MP4 and verify pixel-level correctness.
//
// This is the only way to prove the export output matches the configured edits.
// Duration-only checks (existing ExportPipelineTests) can't catch rendering bugs.

@MainActor
struct ExportFrameVerificationTests {

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - Shared Infrastructure
    // ─────────────────────────────────────────────────────────────────────

    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    /// RGBA pixel at (x, y) in CIImage bottom-left coords.
    private func pixel(_ image: CIImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let ix = CGFloat(x), iy = CGFloat(y)
        let crop = image
            .cropped(to: CGRect(x: ix, y: iy, width: 1, height: 1))
            .transformed(by: CGAffineTransform(translationX: -ix, y: -iy))
        var rgba = [UInt8](repeating: 0, count: 4)
        ciContext.render(crop, toBitmap: &rgba, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return (Double(rgba[0]) / 255.0, Double(rgba[1]) / 255.0,
                Double(rgba[2]) / 255.0, Double(rgba[3]) / 255.0)
    }

    /// Generate a test video where each frame is a KNOWN solid color.
    /// Frame 0 = red, frame 1 = green, frame 2 = blue, then repeats.
    /// This lets us verify which SOURCE frame appears at any composition time.
    private static func generateColorCycleVideo(
        duration: Double,
        size: CGSize = CGSize(width: 160, height: 90),
        fps: Int = 10
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-colorcycle-\(UUID().uuidString).mp4")
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

        let totalFrames = Int(duration * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Colors cycle: red, green, blue
        let colors: [(b: UInt8, g: UInt8, r: UInt8, a: UInt8)] = [
            (0, 0, 220, 255),     // red   (BGRA)
            (0, 220, 0, 255),     // green  (BGRA)
            (220, 0, 0, 255),     // blue   (BGRA)
        ]

        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let pb = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                let c = colors[i % 3]
                for row in 0..<Int(size.height) {
                    for col in 0..<Int(size.width) {
                        let offset = row * bytesPerRow + col * 4
                        ptr[offset + 0] = c.b
                        ptr[offset + 1] = c.g
                        ptr[offset + 2] = c.r
                        ptr[offset + 3] = c.a
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            adaptor.append(pb, withPresentationTime: pts)
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TestError.videoGenFailed(writer.error?.localizedDescription ?? "unknown")
        }
        return url
    }

    /// Generate a solid-color video (every frame identical).
    private static func generateSolidVideo(
        color: (b: UInt8, g: UInt8, r: UInt8, a: UInt8),
        duration: Double,
        size: CGSize = CGSize(width: 160, height: 90),
        fps: Int = 10
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-solid-\(UUID().uuidString).mp4")
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

        let totalFrames = Int(duration * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let pb = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                for row in 0..<Int(size.height) {
                    for col in 0..<Int(size.width) {
                        let offset = row * bytesPerRow + col * 4
                        ptr[offset + 0] = color.b
                        ptr[offset + 1] = color.g
                        ptr[offset + 2] = color.r
                        ptr[offset + 3] = color.a
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            adaptor.append(pb, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TestError.videoGenFailed(writer.error?.localizedDescription ?? "unknown")
        }
        return url
    }

    /// Read frames from an exported MP4 at specific composition times.
    /// Returns CIImages in bottom-left origin (standard CIImage coords).
    private func readFrames(from url: URL, at times: [Double]) async throws -> [CIImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)

        var results: [CIImage] = []
        for t in times {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            let (cgImage, _) = try await generator.image(at: cmTime)
            results.append(CIImage(cgImage: cgImage))
        }
        return results
    }

    /// Run the full export pipeline with given settings and return output URL.
    private func exportFull(
        videoURL: URL,
        sourceSize: CGSize,
        segments: [Segment],
        settings: FrameRenderer.Settings,
        cursorState: CursorOverlayState? = nil
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-verify-\(UUID().uuidString).mp4")

        let service = CompositionExportService()
        let enabledSegments = segments.filter(\.isEnabled)
        try await service.export(
            asset: AVURLAsset(url: videoURL),
            enabledSegments: enabledSegments,
            sourceSize: sourceSize,
            exportSettings: settings,
            cursorOverlayState: cursorState,
            outputURL: outputURL,
            progress: { _ in }
        )
        return outputURL
    }

    private enum TestError: Error {
        case videoGenFailed(String)
        case noFrameAtTime(Double)
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 1. Background Rendering in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportedFrameShowsSolidBackgroundInPaddingArea() async throws {
        // Solid background with padding → padding pixels should be the background color
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 320, height: 180)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 0, g: 200, r: 0, a: 255), // green source
            duration: 2.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let bgColor = CodableColor(red: 0.8, green: 0.1, blue: 0.1) // red background
        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 2, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 40, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(bgColor), frameStyle: .none,
                outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.5])
        let frame = frames[0]

        // Sample a padding pixel (top-left corner, well inside padding zone).
        // CIImage bottom-left origin: y=0 is bottom. Padding at top = y near maxY.
        let topPaddingY = Int(outputSize.height) - 5  // near top in CIImage coords
        let p = pixel(frame, x: 5, y: topPaddingY)

        // Background should be red-ish (0.8, 0.1, 0.1)
        // H.264 compression introduces error, allow generous tolerance
        #expect(p.r > 0.5, "Padding pixel red channel should reflect solid background, got r=\(p.r)")
        #expect(p.g < 0.3, "Padding pixel green channel should be low, got g=\(p.g)")
        #expect(p.b < 0.3, "Padding pixel blue channel should be low, got b=\(p.b)")
    }

    @Test func exportedFrameShowsSourceVideoInRecordingArea() async throws {
        // Source is green, background is red, padding=40.
        // Center of output should contain the green source video.
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 320, height: 180)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 0, g: 200, r: 0, a: 255), // green
            duration: 2.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 2, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 40, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0.8, green: 0.1, blue: 0.1)),
                frameStyle: .none, outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.5])
        let frame = frames[0]

        // Center pixel should be green (source video)
        let cx = Int(outputSize.width) / 2
        let cy = Int(outputSize.height) / 2
        let c = pixel(frame, x: cx, y: cy)

        // H.264 compression shifts values — use relative check (green dominant)
        #expect(c.g > 0.3, "Center pixel should show green source video, got g=\(c.g)")
        #expect(c.g > c.r, "Center pixel green should dominate red (source is green), got r=\(c.r) g=\(c.g)")
    }

    @Test func exportedFrameShowsGradientBackgroundInPadding() async throws {
        // Gradient from black (top-left) to white (bottom-right).
        // With padding, top-left padding pixel should be dark, bottom-right should be light.
        let sourceSize = CGSize(width: 80, height: 45)
        let outputSize = CGSize(width: 240, height: 135)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 128, g: 128, r: 128, a: 255),
            duration: 1.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 1, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 30, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .gradient(
                    CodableColor(red: 0.0, green: 0.0, blue: 0.0),
                    CodableColor(red: 1.0, green: 1.0, blue: 1.0)
                ),
                frameStyle: .none, outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.3])
        let frame = frames[0]

        // Gradient: point0 at (0, height) = top-left in CIImage = color0 (black)
        //           point1 at (width, 0) = bottom-right in CIImage = color1 (white)
        let topLeft = pixel(frame, x: 3, y: Int(outputSize.height) - 3)
        let bottomRight = pixel(frame, x: Int(outputSize.width) - 3, y: 3)

        let topBrightness = (topLeft.r + topLeft.g + topLeft.b) / 3.0
        let bottomBrightness = (bottomRight.r + bottomRight.g + bottomRight.b) / 3.0

        #expect(bottomBrightness > topBrightness + 0.15,
                "Gradient should be lighter at bottom-right (\(bottomBrightness)) than top-left (\(topBrightness))")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 2. Rounded Corners in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportedFrameHasRoundedCorners() async throws {
        // Large corner radius → corner of recording rect should show background, not source.
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 320, height: 180)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 0, g: 220, r: 0, a: 255), // green source
            duration: 1.5, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 1.5, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 30, cornerRadius: 25, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0.9, green: 0.1, blue: 0.1)),
                frameStyle: .none, outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.3])
        let frame = frames[0]

        // Recording rect with padding=30 and output 320x180:
        let recRect = FrameRenderer.calculateRecordingRect(
            sourceSize: sourceSize, outputSize: outputSize, padding: 30
        )

        // The corner of the recording rect should be masked (show background red, not source green)
        // Bottom-left corner in CIImage coords
        let cornerX = Int(recRect.minX) + 2
        let cornerY = Int(recRect.minY) + 2
        let corner = pixel(frame, x: cornerX, y: cornerY)

        // With radius=25, the very corner pixel should be background (red), not source (green)
        #expect(corner.r > corner.g,
                "Corner pixel should be background (red) due to rounded mask, got r=\(corner.r) g=\(corner.g)")

        // Center should still be green (source)
        let centerX = Int(recRect.midX)
        let centerY = Int(recRect.midY)
        let center = pixel(frame, x: centerX, y: centerY)
        #expect(center.g > 0.5, "Center should show green source, got g=\(center.g)")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 3. Disabled Segments Excluded from Export Frames
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportedFramesExcludeDisabledSegmentContent() async throws {
        // 3s video: frame 0-9 = cycling RGB at 10fps.
        // Segment 1 [0-1s]: enabled (red/green/blue frames)
        // Segment 2 [1-2s]: DISABLED
        // Segment 3 [2-3s]: enabled (red/green/blue frames)
        // Export should be ~2s. The first frame after 1s in export should be from source 2s, not 1s.
        let sourceSize = CGSize(width: 160, height: 90)
        let videoURL = try await Self.generateColorCycleVideo(
            duration: 3.0, size: sourceSize, fps: 10
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [
                Segment(startTime: 0, endTime: 1, speed: 1.0, isEnabled: true),
                Segment(startTime: 1, endTime: 2, speed: 1.0, isEnabled: false),
                Segment(startTime: 2, endTime: 3, speed: 1.0, isEnabled: true),
            ],
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0, green: 0, blue: 0)),
                frameStyle: .none, outputSize: sourceSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Verify duration is ~2s (disabled segment removed)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2.0) < 0.3,
                "Export with 1s disabled should be ~2s, got \(duration)s")

        // Read frame at 0.15s — should be from source 0.15s (first enabled segment)
        // Read frame at 1.15s — should be from source 2.15s (third segment, after skipping disabled)
        // Both should have video content (not black)
        let frames = try await readFrames(from: outputURL, at: [0.15, 1.15])
        let firstSegFrame = frames[0]
        let thirdSegFrame = frames[1]

        let cx = Int(sourceSize.width) / 2
        let cy = Int(sourceSize.height) / 2
        let p1 = pixel(firstSegFrame, x: cx, y: cy)
        let p2 = pixel(thirdSegFrame, x: cx, y: cy)

        // Both frames should have actual video content (not black background)
        let brightness1 = max(p1.r, p1.g, p1.b)
        let brightness2 = max(p2.r, p2.g, p2.b)
        #expect(brightness1 > 0.3, "First segment frame should have video content, got max channel=\(brightness1)")
        #expect(brightness2 > 0.3, "Third segment frame should have video content, got max channel=\(brightness2)")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 4. Speed Changes Affect Frame Content
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportAtDoubleSpeedHalvesDuration() async throws {
        // 4s color-cycle video at 2x → export should be ~2s
        let sourceSize = CGSize(width: 160, height: 90)
        let videoURL = try await Self.generateColorCycleVideo(
            duration: 4.0, size: sourceSize, fps: 10
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 4, speed: 2.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0, green: 0, blue: 0)),
                frameStyle: .none, outputSize: sourceSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2.0) < 0.3, "4s at 2x should export as ~2s, got \(duration)s")
    }

    @Test func exportWithMixedSpeedsProducesCorrectDuration() async throws {
        // 6s video: [0-3s @1x] + [3-6s @3x] → 3 + 1 = 4s
        let sourceSize = CGSize(width: 160, height: 90)
        let videoURL = try await Self.generateColorCycleVideo(
            duration: 6.0, size: sourceSize, fps: 10
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [
                Segment(startTime: 0, endTime: 3, speed: 1.0, isEnabled: true),
                Segment(startTime: 3, endTime: 6, speed: 3.0, isEnabled: true),
            ],
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0, green: 0, blue: 0)),
                frameStyle: .none, outputSize: sourceSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        // 3s@1x + 3s@3x = 3 + 1 = 4s (speed ramps adjust slightly)
        #expect(abs(duration - 4.0) < 0.5, "Expected ~4s, got \(duration)s")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 5. Frame Style (Browser Chrome) in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportWithBrowserChromeShowsChromeBar() async throws {
        // Browser chrome adds a dark bar above the video.
        // The chrome bar region should be dark (the chrome fill color is ~0.16, 0.16, 0.18).
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 320, height: 240)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 0, g: 220, r: 0, a: 255), // green
            duration: 1.5, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 1.5, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 30, cornerRadius: 8, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0.9, green: 0.9, blue: 0.9)),
                frameStyle: .browserChrome, outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.3])
        let frame = frames[0]

        // Calculate where chrome bar should be
        let scale = FrameRenderer.pointScale(for: outputSize)
        let chromeH = FrameStyle.browserChrome.chromeHeight * scale
        let recRect = FrameRenderer.calculateRecordingRect(
            sourceSize: sourceSize, outputSize: outputSize,
            padding: 30, chromeHeight: chromeH
        )

        // Chrome bar sits above the recording rect in CIImage coords (bottom-left origin)
        // So the chrome center in CIImage y = recRect.maxY + chromeH/2
        let chromeCenterX = Int(recRect.midX)
        let chromeCenterY = Int(recRect.maxY + chromeH / 2)

        let chromePixel = pixel(frame, x: chromeCenterX, y: chromeCenterY)

        // Chrome fill is (0.16, 0.16, 0.18) — very dark
        let chromeBrightness = (chromePixel.r + chromePixel.g + chromePixel.b) / 3.0
        #expect(chromeBrightness < 0.35,
                "Chrome bar should be dark (~0.17), got brightness=\(chromeBrightness)")

        // Video center should still be green
        let videoPixel = pixel(frame, x: Int(recRect.midX), y: Int(recRect.midY))
        #expect(videoPixel.g > 0.5, "Video center should be green, got g=\(videoPixel.g)")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 6. Shadow in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportWithShadowDarkensAreaBelowRecording() async throws {
        // White background + shadow → area below recording rect should be darker than pure white
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 320, height: 240)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 128, g: 128, r: 128, a: 255),
            duration: 1.5, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 1.5, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 40, cornerRadius: 0, shadowRadius: 20, shadowOpacity: 0.6,
                backgroundStyle: .solid(CodableColor(red: 1.0, green: 1.0, blue: 1.0)),
                frameStyle: .none, outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.3])
        let frame = frames[0]

        let recRect = FrameRenderer.calculateRecordingRect(
            sourceSize: sourceSize, outputSize: outputSize, padding: 40
        )

        // Shadow offsets 8px downward. In CIImage coords (bottom-left), shadow is BELOW the rect.
        // Sample just below the recording rect bottom edge
        let shadowY = max(0, Int(recRect.minY) - 12)
        let shadowPixel = pixel(frame, x: Int(recRect.midX), y: shadowY)

        // Far corner (no shadow influence) — should be near-white background
        let farPixel = pixel(frame, x: 5, y: Int(outputSize.height) - 5)

        let shadowBrightness = (shadowPixel.r + shadowPixel.g + shadowPixel.b) / 3.0
        let farBrightness = (farPixel.r + farPixel.g + farPixel.b) / 3.0

        #expect(shadowBrightness < farBrightness - 0.05,
                "Shadow area (\(shadowBrightness)) should be darker than far background (\(farBrightness))")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 7. Cursor Visible in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportWithCursorShowsCursorInFrame() async throws {
        // Dark source, white cursor at center → cursor pixel should be bright
        let sourceSize = CGSize(width: 160, height: 90)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 10, g: 10, r: 10, a: 255), // near-black source
            duration: 2.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        // Create cursor state with cursor at center, using a small white square as cursor
        let cursorImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 12, height: 12))
        var cursorSettings = CursorSettings()
        cursorSettings.isEnabled = true
        cursorSettings.clickEffectEnabled = false
        cursorSettings.autoZoomEnabled = false

        let cursorState = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0.0, x: 80, y: 45),  // center of source
                SmoothedCursorPoint(timestamp: 2.0, x: 80, y: 45),
            ],
            clicks: [],
            cursorCIImage: cursorImage,
            cursorHotspot: CGPoint(x: 6, y: 6),
            sourceSize: sourceSize,
            captureOrigin: .zero,
            settings: cursorSettings,
            zoomKeyframes: []
        )

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 2, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0, green: 0, blue: 0)),
                frameStyle: .none, outputSize: sourceSize
            ),
            cursorState: cursorState
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.5])
        let frame = frames[0]

        // Cursor is at source center (80, 45). With padding=0, output coords = source coords.
        // CIImage bottom-left: ciY = height - topLeftY = 90 - 45 = 45
        let cursorPixel = pixel(frame, x: 80, y: 45)
        let offCursorPixel = pixel(frame, x: 10, y: 10)

        let cursorBrightness = (cursorPixel.r + cursorPixel.g + cursorPixel.b) / 3.0
        let offBrightness = (offCursorPixel.r + offCursorPixel.g + offCursorPixel.b) / 3.0

        #expect(cursorBrightness > offBrightness + 0.2,
                "Cursor position should be brighter (cursor=\(cursorBrightness)) than background (off=\(offBrightness))")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 8. Click Effect Visible in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportWithClickEffectShowsRingAtClickTime() async throws {
        // Dark source + click effect at center at t=0.5 → ring should be visible shortly after
        let sourceSize = CGSize(width: 160, height: 90)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 10, g: 10, r: 10, a: 255),
            duration: 2.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        var cursorSettings = CursorSettings()
        cursorSettings.isEnabled = true
        cursorSettings.clickEffectEnabled = true
        cursorSettings.clickEffectDuration = 0.4
        cursorSettings.clickEffectMaxRadius = 30
        cursorSettings.clickEffectColor = [1.0, 0.35, 0.37]
        cursorSettings.autoZoomEnabled = false

        let cursorImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))

        let cursorState = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0.0, x: 80, y: 45),
                SmoothedCursorPoint(timestamp: 2.0, x: 80, y: 45),
            ],
            clicks: [
                CursorClick(timestamp: 0.5, x: 80, y: 45, button: .left),
            ],
            cursorCIImage: cursorImage,
            cursorHotspot: CGPoint(x: 2, y: 2),
            sourceSize: sourceSize,
            captureOrigin: .zero,
            settings: cursorSettings,
            zoomKeyframes: []
        )

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 2, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0, green: 0, blue: 0)),
                frameStyle: .none, outputSize: sourceSize
            ),
            cursorState: cursorState
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Read frame during click effect (t=0.6, 0.1s into 0.4s duration)
        // And frame well after click effect (t=1.5)
        let frames = try await readFrames(from: outputURL, at: [0.6, 1.5])
        let duringClick = frames[0]
        let afterClick = frames[1]

        // During click: the ring should add brightness in a ring area around (80, 45)
        // Check at ring radius distance. At t=0.6 (progress=0.25), eased ≈ 0.15625,
        // radius ≈ 30 * 0.15625 ≈ 4.7px from center
        // The ring is small at this point, so check close to center
        let ringPixel = pixel(duringClick, x: 85, y: 45) // slightly offset from center
        let afterPixel = pixel(afterClick, x: 85, y: 45)

        let duringBrightness = max(ringPixel.r, ringPixel.g, ringPixel.b)
        let afterBrightness = max(afterPixel.r, afterPixel.g, afterPixel.b)

        // The click effect adds colored overlay. During click should be brighter than after.
        #expect(duringBrightness > afterBrightness,
                "Area near click should be brighter during effect (\(duringBrightness)) than after (\(afterBrightness))")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 9. Auto-Zoom Crop in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportWithAutoZoomShowsZoomedContent() async throws {
        // Create a two-tone video: left half = red, right half = blue.
        // With 2x zoom focused on the left half, the export should show mostly red.
        let sourceSize = CGSize(width: 160, height: 90)
        let videoURL = try await Self.generateTwoToneVideo(
            leftColor: (b: 0, g: 0, r: 220, a: 255),   // red left half
            rightColor: (b: 220, g: 0, r: 0, a: 255),   // blue right half
            duration: 2.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        var cursorSettings = CursorSettings()
        cursorSettings.isEnabled = false
        cursorSettings.autoZoomEnabled = true

        // Zoom keyframes: 2x zoom focused on left quarter of frame for entire duration
        let focusPoint = CGPoint(x: 40, y: 45) // left quarter center
        let zoomKeyframes = [
            ZoomKeyframe(timestamp: 0.0, zoomLevel: 2.0, focusPoint: focusPoint, easingDuration: 0),
            ZoomKeyframe(timestamp: 2.0, zoomLevel: 2.0, focusPoint: focusPoint, easingDuration: 0),
        ]

        let cursorState = CursorOverlayState(
            smoothedPoints: [],
            clicks: [],
            cursorCIImage: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
            cursorHotspot: .zero,
            sourceSize: sourceSize,
            captureOrigin: .zero,
            settings: cursorSettings,
            zoomKeyframes: zoomKeyframes
        )

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 2, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0, green: 0, blue: 0)),
                frameStyle: .none, outputSize: sourceSize
            ),
            cursorState: cursorState
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.5])
        let frame = frames[0]

        // With 2x zoom on left quarter, the output should show mostly the left (red) half.
        // Center of output should be red.
        let cx = Int(sourceSize.width) / 2
        let cy = Int(sourceSize.height) / 2
        let centerPixel = pixel(frame, x: cx, y: cy)

        #expect(centerPixel.r > 0.4,
                "With 2x zoom on left half, center should be red-ish, got r=\(centerPixel.r)")
        #expect(centerPixel.b < 0.3,
                "With 2x zoom on left half, center should not be blue, got b=\(centerPixel.b)")
    }

    /// Generate a two-tone video: left half one color, right half another.
    private static func generateTwoToneVideo(
        leftColor: (b: UInt8, g: UInt8, r: UInt8, a: UInt8),
        rightColor: (b: UInt8, g: UInt8, r: UInt8, a: UInt8),
        duration: Double,
        size: CGSize = CGSize(width: 160, height: 90),
        fps: Int = 10
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-twotone-\(UUID().uuidString).mp4")
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

        let totalFrames = Int(duration * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let halfWidth = Int(size.width) / 2

        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let pb = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                for row in 0..<Int(size.height) {
                    for col in 0..<Int(size.width) {
                        let offset = row * bytesPerRow + col * 4
                        let c = col < halfWidth ? leftColor : rightColor
                        ptr[offset + 0] = c.b
                        ptr[offset + 1] = c.g
                        ptr[offset + 2] = c.r
                        ptr[offset + 3] = c.a
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            adaptor.append(pb, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TestError.videoGenFailed(writer.error?.localizedDescription ?? "unknown")
        }
        return url
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 10. Border Frame Overlay in Export
    // ─────────────────────────────────────────────────────────────────────

    @Test func exportWithBorderFrameShowsBorderEdge() async throws {
        // Red border (4px) around green source on white background.
        // Edge of recording rect should show red border, not white background or green source.
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 320, height: 240)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 0, g: 220, r: 0, a: 255),
            duration: 1.5, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let borderColor = CodableColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [Segment(startTime: 0, endTime: 1.5, speed: 1.0, isEnabled: true)],
            settings: FrameRenderer.Settings(
                padding: 30, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 1.0, green: 1.0, blue: 1.0)),
                frameStyle: .border(width: 4, color: borderColor),
                outputSize: outputSize
            )
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let frames = try await readFrames(from: outputURL, at: [0.3])
        let frame = frames[0]

        let recRect = FrameRenderer.calculateRecordingRect(
            sourceSize: sourceSize, outputSize: outputSize, padding: 30
        )

        // Sample on the left edge of the recording rect (where border should be)
        let edgeX = Int(recRect.minX)
        let edgeY = Int(recRect.midY)
        let edgePixel = pixel(frame, x: edgeX, y: edgeY)

        // Border should be reddish
        #expect(edgePixel.r > 0.4,
                "Border edge should have red from border overlay, got r=\(edgePixel.r)")
        #expect(edgePixel.r > edgePixel.g,
                "Border should be more red than green, got r=\(edgePixel.r) g=\(edgePixel.g)")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - 11. Full Pipeline: Disabled + Speed + Background + Cursor
    // ─────────────────────────────────────────────────────────────────────

    @Test func fullPipelineCombinesAllEffectsCorrectly() async throws {
        // The integration test: everything together.
        // 6s video: [0-2s @1x enabled] [2-4s disabled] [4-6s @2x enabled]
        // Red solid background, padding=20, corner radius=10
        // Cursor at center, click at t=0.5
        // Expected output: ~3s (2s + 1s from speed)
        let sourceSize = CGSize(width: 160, height: 90)
        let outputSize = CGSize(width: 240, height: 135)
        let videoURL = try await Self.generateSolidVideo(
            color: (b: 0, g: 180, r: 0, a: 255), // green
            duration: 6.0, size: sourceSize
        )
        defer { try? FileManager.default.removeItem(at: videoURL) }

        var cursorSettings = CursorSettings()
        cursorSettings.isEnabled = true
        cursorSettings.clickEffectEnabled = true
        cursorSettings.clickEffectDuration = 0.3
        cursorSettings.clickEffectMaxRadius = 20
        cursorSettings.autoZoomEnabled = false

        let cursorImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let cursorState = CursorOverlayState(
            smoothedPoints: [
                SmoothedCursorPoint(timestamp: 0.0, x: 80, y: 45),
                SmoothedCursorPoint(timestamp: 6.0, x: 80, y: 45),
            ],
            clicks: [CursorClick(timestamp: 0.5, x: 80, y: 45, button: .left)],
            cursorCIImage: cursorImage,
            cursorHotspot: CGPoint(x: 4, y: 4),
            sourceSize: sourceSize,
            captureOrigin: .zero,
            settings: cursorSettings,
            zoomKeyframes: []
        )

        let outputURL = try await exportFull(
            videoURL: videoURL,
            sourceSize: sourceSize,
            segments: [
                Segment(startTime: 0, endTime: 2, speed: 1.0, isEnabled: true),
                Segment(startTime: 2, endTime: 4, speed: 1.0, isEnabled: false),
                Segment(startTime: 4, endTime: 6, speed: 2.0, isEnabled: true),
            ],
            settings: FrameRenderer.Settings(
                padding: 20, cornerRadius: 10, shadowRadius: 0, shadowOpacity: 0,
                backgroundStyle: .solid(CodableColor(red: 0.8, green: 0.1, blue: 0.1)),
                frameStyle: .none, outputSize: outputSize
            ),
            cursorState: cursorState
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Verify duration: 2s@1x + skip + 2s@2x = 3s
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 3.0) < 0.5, "Expected ~3s, got \(duration)s")

        // Verify frame at 1.0s (mid first segment): should have content
        let frames = try await readFrames(from: outputURL, at: [1.0])
        let frame = frames[0]

        let recRect = FrameRenderer.calculateRecordingRect(
            sourceSize: sourceSize, outputSize: outputSize, padding: 20
        )

        // Padding area should be red background
        let padPixel = pixel(frame, x: 3, y: Int(outputSize.height) - 3)
        #expect(padPixel.r > 0.5, "Padding should be red background, got r=\(padPixel.r)")

        // Video center should be green source
        let vidPixel = pixel(frame, x: Int(recRect.midX), y: Int(recRect.midY))
        #expect(vidPixel.g > 0.3, "Video center should show green source, got g=\(vidPixel.g)")

        // Corner of recording rect should be masked (red background visible due to corner radius)
        let cornerPixel = pixel(frame, x: Int(recRect.minX) + 1, y: Int(recRect.minY) + 1)
        #expect(cornerPixel.r > cornerPixel.g,
                "Rounded corner should show red background, got r=\(cornerPixel.r) g=\(cornerPixel.g)")
    }
}
