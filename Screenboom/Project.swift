import Foundation
import AVFoundation
import SwiftUI

// MARK: - Persisted State

struct SavedState: Codable {
    var sourceURLBookmark: Data?
    var splitPoints: [Double]
    var segmentStates: [SavedSegment]
    var gradientColor1: [Double] // [r, g, b]
    var gradientColor2: [Double]
    var padding: Double
    var cornerRadius: Double
    var shadowRadius: Double
    var shadowOpacity: Double
    var outputWidth: Double
    var outputHeight: Double
    var playheadTime: Double
    var showThumbnails: Bool?

    struct SavedSegment: Codable {
        var startTime: Double
        var endTime: Double
        var speed: Double
        var isEnabled: Bool
    }

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Screenboom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("project-state.json")
    }()

    func write() {
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Failed to save state: \(error)")
        }
    }

    static func load() -> SavedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }
}

// MARK: - Project

@Observable
final class Project {
    var sourceURL: URL?
    var asset: AVAsset?
    var videoSize: CGSize = .zero
    var duration: CMTime = .zero

    var player: AVPlayer?
    var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var boundaryObserver: Any?

    var splitPoints: [Double] = []
    var segments: [Segment] = []
    var selectedSegmentId: UUID?

    var gradientColor1: Color = Color(red: 0.08, green: 0.08, blue: 0.12)
    var gradientColor2: Color = Color(red: 0.18, green: 0.12, blue: 0.28)
    var padding: CGFloat = 60
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 30
    var shadowOpacity: CGFloat = 0.5

    var outputWidth: CGFloat = 1920
    var outputHeight: CGFloat = 1080

    var currentTime: Double = 0
    var playheadTime: Double = 0
    var isPlaying: Bool = false

    var thumbnails: [CGImage] = []

    var showThumbnails: Bool = true

    var isExporting: Bool = false
    var exportProgress: Double = 0

    private var saveTask: Task<Void, Never>?

    // MARK: - Speed Ramping

    private var speedRampTimer: Timer?
    private var speedRampStartDate: Date?
    private var speedRampFromRate: Float = 1.0
    private var speedRampToRate: Float = 1.0
    private let speedRampDuration: TimeInterval = 0.3

    private var isSpeedRamping: Bool { speedRampTimer != nil }

    private func startSpeedRamp(to targetRate: Float) {
        let currentRate = player?.rate ?? 1.0
        guard currentRate != 0, abs(currentRate - targetRate) > 0.01 else { return }

        speedRampFromRate = currentRate
        speedRampToRate = targetRate
        speedRampStartDate = Date()

        speedRampTimer?.invalidate()
        speedRampTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.speedRampStartDate else { return }
            let elapsed = Date().timeIntervalSince(startDate)
            let t = min(1.0, elapsed / self.speedRampDuration)

            // Smoothstep ease-in-out
            let eased = Float(t * t * (3.0 - 2.0 * t))
            let rate = self.speedRampFromRate + eased * (self.speedRampToRate - self.speedRampFromRate)

            self.player?.rate = rate

            if t >= 1.0 {
                self.speedRampTimer?.invalidate()
                self.speedRampTimer = nil
                self.speedRampStartDate = nil
            }
        }
    }

    private func cancelSpeedRamp() {
        speedRampTimer?.invalidate()
        speedRampTimer = nil
        speedRampStartDate = nil
    }

    // MARK: - Boundary Observers (disabled segment skip)

    private func updateBoundaryObservers() {
        if let token = boundaryObserver, let player {
            player.removeTimeObserver(token)
            boundaryObserver = nil
        }

        guard let player else { return }

        let disabledTimes = segments
            .filter { !$0.isEnabled }
            .map { NSValue(time: CMTime(seconds: $0.startTime, preferredTimescale: 600)) }

        guard !disabledTimes.isEmpty else { return }

        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: disabledTimes,
            queue: .main
        ) { [weak self] in
            guard let self, let player = self.player else { return }
            let time = player.currentTime().seconds
            guard let seg = self.segments.first(where: { !$0.isEnabled && time >= $0.startTime - 0.01 && time < $0.endTime }) else { return }

            self.cancelSpeedRamp()
            if let next = self.segments.first(where: { $0.isEnabled && $0.startTime >= seg.endTime - 0.001 }) {
                player.seek(to: CMTime(seconds: next.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player.rate = Float(next.speed)
            } else {
                player.pause()
                self.isPlaying = false
            }
        }
    }

    // MARK: - Undo/Redo

    private struct UndoSnapshot {
        let splitPoints: [Double]
        let segments: [(startTime: Double, endTime: Double, speed: Double, isEnabled: Bool)]
    }

    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func captureSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            splitPoints: splitPoints,
            segments: segments.map { ($0.startTime, $0.endTime, $0.speed, $0.isEnabled) }
        )
    }

    private func pushUndo() {
        undoStack.append(captureSnapshot())
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(captureSnapshot())
        restoreSnapshot(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(captureSnapshot())
        restoreSnapshot(snapshot)
    }

    private func restoreSnapshot(_ snapshot: UndoSnapshot) {
        splitPoints = snapshot.splitPoints
        segments = snapshot.segments.map {
            Segment(startTime: $0.startTime, endTime: $0.endTime, speed: $0.speed, isEnabled: $0.isEnabled)
        }
        selectedSegmentId = nil
        updateBoundaryObservers()
        saveState()
    }

    var totalOutputDuration: Double {
        segments.filter(\.isEnabled).reduce(0) { $0 + $1.outputDuration }
    }

    init() {
        restoreState()
    }

    // MARK: - Persistence

    func saveState() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.writeStateNow()
        }
    }

    private func writeStateNow() {
        var bookmark: Data?
        if let url = sourceURL {
            bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        let nsColor1 = NSColor(gradientColor1).usingColorSpace(.sRGB) ?? NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
        let nsColor2 = NSColor(gradientColor2).usingColorSpace(.sRGB) ?? NSColor(red: 0.18, green: 0.12, blue: 0.28, alpha: 1)

        let state = SavedState(
            sourceURLBookmark: bookmark,
            splitPoints: splitPoints,
            segmentStates: segments.map {
                SavedState.SavedSegment(startTime: $0.startTime, endTime: $0.endTime, speed: $0.speed, isEnabled: $0.isEnabled)
            },
            gradientColor1: [nsColor1.redComponent, nsColor1.greenComponent, nsColor1.blueComponent],
            gradientColor2: [nsColor2.redComponent, nsColor2.greenComponent, nsColor2.blueComponent],
            padding: Double(padding),
            cornerRadius: Double(cornerRadius),
            shadowRadius: Double(shadowRadius),
            shadowOpacity: Double(shadowOpacity),
            outputWidth: Double(outputWidth),
            outputHeight: Double(outputHeight),
            playheadTime: playheadTime,
            showThumbnails: showThumbnails
        )
        state.write()
    }

    private func restoreState() {
        guard let state = SavedState.load() else { return }

        // Restore visual settings immediately
        gradientColor1 = Color(red: state.gradientColor1[safe: 0] ?? 0.08,
                               green: state.gradientColor1[safe: 1] ?? 0.08,
                               blue: state.gradientColor1[safe: 2] ?? 0.12)
        gradientColor2 = Color(red: state.gradientColor2[safe: 0] ?? 0.18,
                               green: state.gradientColor2[safe: 1] ?? 0.12,
                               blue: state.gradientColor2[safe: 2] ?? 0.28)
        padding = CGFloat(state.padding)
        cornerRadius = CGFloat(state.cornerRadius)
        shadowRadius = CGFloat(state.shadowRadius)
        shadowOpacity = CGFloat(state.shadowOpacity)
        outputWidth = CGFloat(state.outputWidth)
        outputHeight = CGFloat(state.outputHeight)
        showThumbnails = state.showThumbnails ?? true

        // Restore video via bookmark
        guard let bookmark = state.sourceURLBookmark else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }
        _ = url.startAccessingSecurityScopedResource()

        let loadedAsset = AVAsset(url: url)
        self.sourceURL = url
        self.asset = loadedAsset

        Task {
            do {
                let tracks = try await loadedAsset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else { return }
                let size = try await videoTrack.load(.naturalSize)
                let dur = try await loadedAsset.load(.duration)

                self.videoSize = size
                self.duration = dur

                // Restore splits and segments from saved state
                self.splitPoints = state.splitPoints
                self.segments = state.segmentStates.map {
                    Segment(startTime: $0.startTime, endTime: $0.endTime, speed: $0.speed, isEnabled: $0.isEnabled)
                }

                // If no segments were saved, create default
                if self.segments.isEmpty {
                    self.segments = [Segment(startTime: 0, endTime: dur.seconds, speed: 1.0, isEnabled: true)]
                }

                self.rebuildPlayer()
                self.generateThumbnails()

                // Restore playhead
                if state.playheadTime > 0 {
                    self.playheadTime = state.playheadTime
                    self.currentTime = state.playheadTime
                    let target = CMTime(seconds: state.playheadTime, preferredTimescale: 600)
                    await self.player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            } catch {
                print("Failed to restore video: \(error)")
            }
        }
    }

    // MARK: - Load Video

    func loadVideo(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        let loadedAsset = AVAsset(url: url)
        self.sourceURL = url
        self.asset = loadedAsset

        Task {
            do {
                let tracks = try await loadedAsset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else { return }
                let size = try await videoTrack.load(.naturalSize)
                let dur = try await loadedAsset.load(.duration)

                self.videoSize = size
                self.duration = dur
                self.splitPoints = []
                self.segments = [
                    Segment(startTime: 0, endTime: dur.seconds, speed: 1.0, isEnabled: true)
                ]
                self.rebuildPlayer()
                self.generateThumbnails()
                self.saveState()
            } catch {
                print("Failed to load video: \(error)")
            }
        }
    }

    // MARK: - Player

    func rebuildPlayer() {
        guard let asset else { return }

        cancelSpeedRamp()

        let savedTime = player?.currentTime()
        let wasPlaying = isPlaying

        if let token = timeObserver, let player {
            player.removeTimeObserver(token)
            timeObserver = nil
        }
        if let token = boundaryObserver, let player {
            player.removeTimeObserver(token)
            boundaryObserver = nil
        }

        let videoComp = FrameRenderer.makeVideoComposition(
            for: asset,
            sourceSize: videoSize,
            settings: renderSettings
        )

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = videoComp

        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
        playerItem = item

        if let savedTime {
            player?.seek(to: min(savedTime, duration), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if wasPlaying { player?.play() }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            self.isPlaying = self.player?.rate != 0

            if self.player?.rate != 0 {
                self.playheadTime = time.seconds
                self.handlePlaybackSegmentLogic(at: time.seconds)
            }
        }

        updateBoundaryObservers()
    }

    private func handlePlaybackSegmentLogic(at time: Double) {
        guard let seg = segments.first(where: { time >= $0.startTime && time < $0.endTime }) else {
            return
        }

        if !seg.isEnabled {
            cancelSpeedRamp()
            // Skip to next enabled segment
            if let next = segments.first(where: { $0.isEnabled && $0.startTime >= seg.endTime - 0.001 }) {
                player?.seek(to: CMTime(seconds: next.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player?.rate = Float(next.speed)
            } else {
                // No more enabled segments ahead — pause
                player?.pause()
            }
        } else {
            // Smoothly ramp to the target speed at segment transitions
            let targetRate = Float(seg.speed)
            if let rate = player?.rate, rate != 0 {
                if isSpeedRamping {
                    // If target changed during ramp, start new ramp from current rate
                    if abs(speedRampToRate - targetRate) > 0.01 {
                        startSpeedRamp(to: targetRate)
                    }
                } else if abs(rate - targetRate) > 0.01 {
                    startSpeedRamp(to: targetRate)
                }
            }
        }
    }

    func updateVisuals() {
        guard let asset else { return }
        let videoComp = FrameRenderer.makeVideoComposition(
            for: asset,
            sourceSize: videoSize,
            settings: renderSettings
        )
        playerItem?.videoComposition = videoComp
        saveState()
    }

    var renderSettings: FrameRenderer.Settings {
        FrameRenderer.Settings(
            padding: padding,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity,
            gradientColor1: NSColor(gradientColor1),
            gradientColor2: NSColor(gradientColor2),
            outputSize: CGSize(width: outputWidth, height: outputHeight)
        )
    }

    // MARK: - Segments

    func addSplit(at time: Double) {
        let t = (time * 100).rounded() / 100
        guard t > 0.05, t < duration.seconds - 0.05 else { return }
        guard !splitPoints.contains(where: { abs($0 - t) < 0.05 }) else { return }
        pushUndo()
        splitPoints.append(t)
        splitPoints.sort()
        rebuildSegments()
        saveState()
    }

    func removeSplit(at index: Int) {
        guard splitPoints.indices.contains(index) else { return }
        pushUndo()
        splitPoints.remove(at: index)
        rebuildSegments()
        saveState()
    }

    private func rebuildSegments() {
        let times = [0.0] + splitPoints + [duration.seconds]
        var newSegments: [Segment] = []

        for i in 0..<(times.count - 1) {
            // Find old segment that CONTAINS this new range (handles splits correctly)
            let existing = segments.first {
                $0.startTime <= times[i] + 0.02 && $0.endTime >= times[i + 1] - 0.02
            }
            newSegments.append(Segment(
                startTime: times[i],
                endTime: times[i + 1],
                speed: existing?.speed ?? 1.0,
                isEnabled: existing?.isEnabled ?? true
            ))
        }

        segments = newSegments
        updateBoundaryObservers()
    }

    func toggleSegment(_ id: UUID) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        segments[idx].isEnabled.toggle()
        updateBoundaryObservers()
        saveState()
    }

    func setSpeed(_ speed: Double, for id: UUID) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        segments[idx].speed = max(0.25, min(32.0, speed))
        saveState()
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 {
            // Commit preview position as playhead
            playheadTime = currentTime
            // If in a disabled segment, skip to next enabled first
            let time = currentTime
            if let seg = segments.first(where: { time >= $0.startTime && time < $0.endTime }) {
                if !seg.isEnabled {
                    if let next = segments.first(where: { $0.isEnabled && $0.startTime >= seg.endTime - 0.001 }) {
                        player.seek(to: CMTime(seconds: next.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        player.rate = Float(next.speed)
                    }
                    // No enabled segments ahead — don't start playback
                } else {
                    player.rate = Float(seg.speed)
                }
            } else {
                player.play()
            }
        } else {
            player.pause()
            cancelSpeedRamp()
        }
        isPlaying = player.rate != 0
    }

    func seek(toFraction fraction: Double) {
        guard let player else { return }
        let target = CMTimeMultiplyByFloat64(duration, multiplier: max(0, min(1, fraction)))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Time mapping

    func outputFractionToSourceFraction(_ outputFraction: Double) -> Double {
        let outputTime = outputFraction * totalOutputDuration
        let enabledSegments = segments.filter(\.isEnabled)
        var acc = 0.0
        for seg in enabledSegments {
            if outputTime <= acc + seg.outputDuration + 0.001 {
                let within = (outputTime - acc) * seg.speed
                return (seg.startTime + within) / duration.seconds
            }
            acc += seg.outputDuration
        }
        return 1.0
    }

    func sourceFractionToOutputFraction(_ sourceFraction: Double) -> Double {
        let sourceTime = sourceFraction * duration.seconds
        let enabledSegments = segments.filter(\.isEnabled)
        var acc = 0.0
        let total = totalOutputDuration
        guard total > 0 else { return 0 }

        for seg in enabledSegments {
            if sourceTime >= seg.startTime && sourceTime <= seg.endTime {
                let within = (sourceTime - seg.startTime) / seg.speed
                return (acc + within) / total
            }
            acc += seg.outputDuration
        }

        // Source time is in a disabled segment — snap to nearest enabled boundary
        var bestFraction = 0.0
        var bestDist = Double.infinity
        acc = 0
        for seg in enabledSegments {
            let startDist = abs(sourceTime - seg.startTime)
            let endDist = abs(sourceTime - seg.endTime)
            if startDist < bestDist {
                bestDist = startDist
                bestFraction = acc / total
            }
            if endDist < bestDist {
                bestDist = endDist
                bestFraction = (acc + seg.outputDuration) / total
            }
            acc += seg.outputDuration
        }
        return max(0, min(1, bestFraction))
    }

    // MARK: - Thumbnails

    func generateThumbnails() {
        guard let asset else { return }
        let dur = duration.seconds
        guard dur > 0 else { return }

        let capturedAsset = asset
        Task.detached {
            let generator = AVAssetImageGenerator(asset: capturedAsset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 120)

            let count = max(20, min(80, Int(dur * 2)))
            let interval = dur / Double(count)
            var images: [CGImage] = []

            for i in 0..<count {
                let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
                if let result = try? await generator.image(at: time) {
                    images.append(result.image)
                }
            }

            await MainActor.run {
                self.thumbnails = images
            }
        }
    }

    // MARK: - Export

    func startExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Screenboom Export.mp4"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                await self.runExport(to: url)
            }
        }
    }

    private func runExport(to url: URL) async {
        isExporting = true
        exportProgress = 0

        let enabledSegments = segments.filter(\.isEnabled)
        guard let asset, !enabledSegments.isEmpty else {
            isExporting = false
            return
        }

        try? FileManager.default.removeItem(at: url)

        let composition = CompositionEngine.buildComposition(asset: asset, segments: enabledSegments)
        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: videoSize,
            settings: renderSettings
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("Export failed: could not create export session")
            isExporting = false
            return
        }

        session.outputURL = url
        session.outputFileType = .mp4
        session.videoComposition = videoComp

        // Poll progress
        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self.exportProgress = Double(session.progress)
            }
        }

        await session.export()
        progressTask.cancel()

        if session.status == .completed {
            isExporting = false
            exportProgress = 1.0
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } else {
            print("Export failed: \(session.error?.localizedDescription ?? "unknown")")
            isExporting = false
        }
    }
}

// MARK: - Segment

struct Segment: Identifiable, Equatable {
    let id = UUID()
    var startTime: Double
    var endTime: Double
    var speed: Double
    var isEnabled: Bool

    var duration: Double { endTime - startTime }
    var outputDuration: Double { duration / speed }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
