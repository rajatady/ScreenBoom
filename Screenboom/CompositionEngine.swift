import AVFoundation

enum CompositionEngine {

    // MARK: - Export Segment (source range + speed)

    private struct ExportSegment {
        var sourceStart: Double
        var sourceEnd: Double
        var speed: Double
        var sourceDuration: Double { sourceEnd - sourceStart }
    }

    // MARK: - Speed Ramp Expansion

    /// Expands segments into sub-segments with smooth speed ramps at boundaries.
    /// At each boundary where adjacent segments have different speeds, a 0.3s ramp zone
    /// (0.15s from each side) is split into 10 micro-steps with smoothstep-interpolated speeds.
    nonisolated private static func expandWithRamps(_ segments: [Segment], halfRampDuration: Double = 0.15) -> [ExportSegment] {
        guard !segments.isEmpty else { return [] }

        // Identify ramp zones at each boundary
        struct RampZone {
            var boundaryIndex: Int   // between segments[i] and segments[i+1]
            var preRampStart: Double // source time where ramp begins (in segment i)
            var postRampEnd: Double  // source time where ramp ends (in segment i+1)
            var fromSpeed: Double
            var toSpeed: Double
        }

        var rampZones: [RampZone] = []
        for i in 0..<(segments.count - 1) {
            let a = segments[i]
            let b = segments[i + 1]
            if abs(a.speed - b.speed) > 0.01 {
                let preDur = min(halfRampDuration, a.duration / 2)
                let postDur = min(halfRampDuration, b.duration / 2)
                rampZones.append(RampZone(
                    boundaryIndex: i,
                    preRampStart: a.endTime - preDur,
                    postRampEnd: b.startTime + postDur,
                    fromSpeed: a.speed,
                    toSpeed: b.speed
                ))
            }
        }

        var result: [ExportSegment] = []

        for (i, seg) in segments.enumerated() {
            let rampAtEnd = rampZones.first { $0.boundaryIndex == i }
            let rampAtStart = rampZones.first { $0.boundaryIndex == i - 1 }

            let mainStart = rampAtStart?.postRampEnd ?? seg.startTime
            let mainEnd = rampAtEnd?.preRampStart ?? seg.endTime

            // Ramp-in micro-segments (second half of previous boundary's ramp)
            if let ramp = rampAtStart {
                let totalRampDur = ramp.postRampEnd - ramp.preRampStart
                let localStart = seg.startTime
                let localEnd = ramp.postRampEnd
                let steps = 5
                let stepDur = (localEnd - localStart) / Double(steps)
                for s in 0..<steps {
                    let midTime = localStart + (Double(s) + 0.5) * stepDur
                    let globalT = (midTime - ramp.preRampStart) / totalRampDur
                    let eased = globalT * globalT * (3.0 - 2.0 * globalT)
                    let speed = ramp.fromSpeed + (ramp.toSpeed - ramp.fromSpeed) * eased
                    result.append(ExportSegment(
                        sourceStart: localStart + Double(s) * stepDur,
                        sourceEnd: localStart + Double(s + 1) * stepDur,
                        speed: speed
                    ))
                }
            }

            // Main portion at segment's native speed
            if mainEnd > mainStart + 0.001 {
                result.append(ExportSegment(
                    sourceStart: mainStart,
                    sourceEnd: mainEnd,
                    speed: seg.speed
                ))
            }

            // Ramp-out micro-segments (first half of next boundary's ramp)
            if let ramp = rampAtEnd {
                let totalRampDur = ramp.postRampEnd - ramp.preRampStart
                let localStart = ramp.preRampStart
                let localEnd = seg.endTime
                let steps = 5
                let stepDur = (localEnd - localStart) / Double(steps)
                for s in 0..<steps {
                    let midTime = localStart + (Double(s) + 0.5) * stepDur
                    let globalT = (midTime - ramp.preRampStart) / totalRampDur
                    let eased = globalT * globalT * (3.0 - 2.0 * globalT)
                    let speed = ramp.fromSpeed + (ramp.toSpeed - ramp.fromSpeed) * eased
                    result.append(ExportSegment(
                        sourceStart: localStart + Double(s) * stepDur,
                        sourceEnd: localStart + Double(s + 1) * stepDur,
                        speed: speed
                    ))
                }
            }
        }

        return result
    }

    // MARK: - Build Composition

    nonisolated static func buildComposition(
        asset: AVAsset,
        segments: [Segment]
    ) -> AVMutableComposition {
        let composition = AVMutableComposition()

        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first,
              let compositionTrack = composition.addMutableTrack(
                  withMediaType: .video,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return composition
        }

        // Expand segments with speed ramps at boundaries
        let expandedSegments = expandWithRamps(segments)

        // Insert all segments at their original durations
        var insertionPoints: [(start: CMTime, duration: CMTime, speed: Double)] = []
        var currentTime = CMTime.zero

        for seg in expandedSegments {
            let start = CMTime(seconds: seg.sourceStart, preferredTimescale: 600)
            let end = CMTime(seconds: seg.sourceEnd, preferredTimescale: 600)
            let range = CMTimeRange(start: start, end: end)

            do {
                try compositionTrack.insertTimeRange(range, of: sourceVideoTrack, at: currentTime)
                insertionPoints.append((
                    start: currentTime,
                    duration: range.duration,
                    speed: seg.speed
                ))
                currentTime = currentTime + range.duration
            } catch {
                print("Failed to insert segment: \(error)")
            }
        }

        // Apply speed changes backward to preserve positions
        for point in insertionPoints.reversed() {
            if abs(point.speed - 1.0) > 0.01 {
                let targetDuration = CMTimeMultiplyByFloat64(point.duration, multiplier: 1.0 / point.speed)
                let range = CMTimeRange(start: point.start, duration: point.duration)
                compositionTrack.scaleTimeRange(range, toDuration: targetDuration)
            }
        }

        return composition
    }

    nonisolated static func export(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition,
        outputSize: CGSize,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Reader
        let reader = try AVAssetReader(asset: composition)
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: composition.tracks(withMediaType: .video),
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        readerOutput.videoComposition = videoComposition
        guard reader.canAdd(readerOutput) else {
            throw ExportError.cannotConfigureReader
        }
        reader.add(readerOutput)

        // Writer — H.264 for maximum compatibility (HEVC causes QuickTime Player
        // duration bugs on macOS). Bitrate scaled by resolution.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let pixelCount = Int(outputSize.width * outputSize.height)
        let bitrate = min(80_000_000, max(20_000_000, pixelCount * 15))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ] as [String: Any]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw ExportError.cannotConfigureWriter
        }
        writer.add(writerInput)

        // Start
        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error)
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalDuration = composition.duration.seconds
        let minFrameInterval = 1.0 / 60.0
        var lastWrittenPTS: Double = -1

        // Process frames — throttle to 60fps output.
        // Speed-scaled compositions produce >60fps (e.g. 6x speed = 360fps effective).
        // Writing all frames causes QuickTime Player duration bugs with both H.264 and HEVC.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.screenboom.export")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

                        // Write first frame always, then only if enough time has passed
                        if lastWrittenPTS < 0 || (pts - lastWrittenPTS) >= minFrameInterval * 0.9 {
                            if totalDuration > 0 {
                                progress(min(1.0, pts / totalDuration))
                            }
                            writerInput.append(sampleBuffer)
                            lastWrittenPTS = pts
                        }
                    } else {
                        writerInput.markAsFinished()

                        if reader.status == .failed {
                            writer.cancelWriting()
                            continuation.resume(throwing: ExportError.readerFailed(reader.error))
                            return
                        }

                        writer.finishWriting {
                            if writer.status == .completed {
                                progress(1.0)
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: ExportError.writerFailed(writer.error))
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    // MARK: - Time Remap Table (for cursor overlay in export)

    /// Builds a mapping from composition time → source time, accounting for speed changes.
    /// The CIFilter handler receives composition time, but cursor events are in source time.
    nonisolated static func buildTimeRemapTable(segments: [Segment]) -> TimeRemapTable {
        guard !segments.isEmpty else { return TimeRemapTable(entries: []) }

        let expandedSegments = expandWithRamps(segments)
        var entries: [TimeRemapEntry] = []

        // Walk through expanded segments, computing composition time for each source time
        var compositionTime = 0.0
        let samplesPerSecond = 60.0  // 60 samples per second of composition time

        for seg in expandedSegments {
            let sourceDuration = seg.sourceDuration
            let compositionDuration = sourceDuration / seg.speed
            let steps = max(1, Int(compositionDuration * samplesPerSecond))
            let compStep = compositionDuration / Double(steps)
            let sourceStep = sourceDuration / Double(steps)

            for i in 0...steps {
                entries.append(TimeRemapEntry(
                    compositionTime: compositionTime + Double(i) * compStep,
                    sourceTime: seg.sourceStart + Double(i) * sourceStep
                ))
            }

            compositionTime += compositionDuration
        }

        return TimeRemapTable(entries: entries)
    }

    enum ExportError: Error, LocalizedError {
        case cannotConfigureReader
        case cannotConfigureWriter
        case readerFailed(Error?)
        case writerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .cannotConfigureReader: return "Cannot configure video reader"
            case .cannotConfigureWriter: return "Cannot configure video writer"
            case .readerFailed(let e): return "Reader failed: \(e?.localizedDescription ?? "unknown")"
            case .writerFailed(let e): return "Writer failed: \(e?.localizedDescription ?? "unknown")"
            }
        }
    }
}
