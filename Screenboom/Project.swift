import Foundation
import AVFoundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.trymagically.Screenboom", category: "Project")

// MARK: - Persisted State

struct SavedState: Codable {
    var sourceURLBookmark: Data?
    var sourceURLPath: String?
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

    // Cursor settings (all optional for backward compatibility)
    var cursorEnabled: Bool?
    var cursorStyle: String?
    var cursorSize: Double?
    var clickEffectEnabled: Bool?
    var clickEffectColor: [Double]?
    var clickEffectMaxRadius: Double?
    var clickEffectDuration: Double?
    var autoZoomEnabled: Bool?
    var autoZoomLevel: Double?
    var autoZoomSensitivity: String?
    var zoomRegions: [SavedZoomRegion]?

    struct SavedZoomRegion: Codable {
        var id: String
        var startTime: Double
        var endTime: Double
        var zoomLevel: Double
        var focusX: Double
        var focusY: Double
        var isEnabled: Bool
    }

    struct SavedSegment: Codable {
        var startTime: Double
        var endTime: Double
        var speed: Double
        var isEnabled: Bool
    }

    static let legacyFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Screenboom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("project-state.json")
    }()

    func write(to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save state: \(error)")
        }
    }

    static func load(from url: URL) -> SavedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
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

    var cursorMetadataURL: URL?
    var recordingSession: RecordingSession?
    var cursorSettings = CursorSettings()
    var cursorOverlayState: CursorOverlayState?
    private var cursorMetadata: CursorMetadataFile?

    var hasCursorData: Bool { cursorMetadata != nil }

    var zoomRegions: [ZoomRegion] = []
    var selectedZoomRegionID: UUID?

    var currentProjectID: UUID?
    var store: ProjectStore?
    var onVideoLoaded: ((UUID, CGSize, Double) -> Void)?

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

    init() {}

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
            // Try security-scoped first (user-selected files), fall back to regular (app-owned recordings)
            do {
                bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                logger.warning("writeStateNow: security-scoped bookmark failed: \(error.localizedDescription)")
            }
            if bookmark == nil {
                do {
                    bookmark = try url.bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                } catch {
                    logger.warning("writeStateNow: regular bookmark also failed: \(error.localizedDescription)")
                }
            }
            logger.warning("writeStateNow: bookmark=\(bookmark != nil), path=\(url.path)")
        }

        let nsColor1 = NSColor(gradientColor1).usingColorSpace(.sRGB) ?? NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
        let nsColor2 = NSColor(gradientColor2).usingColorSpace(.sRGB) ?? NSColor(red: 0.18, green: 0.12, blue: 0.28, alpha: 1)

        let savedZoomRegions: [SavedState.SavedZoomRegion]? = zoomRegions.isEmpty ? nil : zoomRegions.map {
            SavedState.SavedZoomRegion(
                id: $0.id.uuidString,
                startTime: $0.startTime,
                endTime: $0.endTime,
                zoomLevel: Double($0.zoomLevel),
                focusX: $0.focusX,
                focusY: $0.focusY,
                isEnabled: $0.isEnabled
            )
        }

        let state = SavedState(
            sourceURLBookmark: bookmark,
            sourceURLPath: sourceURL?.path,
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
            showThumbnails: showThumbnails,
            cursorEnabled: cursorSettings.isEnabled,
            cursorStyle: cursorSettings.style.rawValue,
            cursorSize: Double(cursorSettings.size),
            clickEffectEnabled: cursorSettings.clickEffectEnabled,
            clickEffectColor: cursorSettings.clickEffectColor,
            clickEffectMaxRadius: Double(cursorSettings.clickEffectMaxRadius),
            clickEffectDuration: cursorSettings.clickEffectDuration,
            autoZoomEnabled: cursorSettings.autoZoomEnabled,
            autoZoomLevel: Double(cursorSettings.autoZoomLevel),
            autoZoomSensitivity: cursorSettings.autoZoomSensitivity.rawValue,
            zoomRegions: savedZoomRegions
        )
        guard let projectID = currentProjectID, let store else { return }
        state.write(to: store.stateFileURL(for: projectID))
    }

    // MARK: - Multi-Project

    func loadProject(info: ProjectInfo, store: ProjectStore) {
        self.store = store
        self.currentProjectID = info.id

        let stateURL = store.stateFileURL(for: info.id)
        logger.warning("loadProject: attempting to load state from \(stateURL.path)")
        guard let state = SavedState.load(from: stateURL) else {
            logger.error("loadProject: FAILED — state file missing or undecodable at \(stateURL.path)")
            return
        }
        logger.warning("loadProject: state loaded, bookmark exists: \(state.sourceURLBookmark != nil)")

        // Restore visual settings
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

        // Restore cursor settings
        if let enabled = state.cursorEnabled { cursorSettings.isEnabled = enabled }
        if let style = state.cursorStyle, let s = CursorStyle(rawValue: style) { cursorSettings.style = s }
        if let size = state.cursorSize { cursorSettings.size = CGFloat(size) }
        if let clickEnabled = state.clickEffectEnabled { cursorSettings.clickEffectEnabled = clickEnabled }
        if let clickColor = state.clickEffectColor { cursorSettings.clickEffectColor = clickColor }
        if let maxR = state.clickEffectMaxRadius { cursorSettings.clickEffectMaxRadius = CGFloat(maxR) }
        if let clickDur = state.clickEffectDuration { cursorSettings.clickEffectDuration = clickDur }
        if let zoomEnabled = state.autoZoomEnabled { cursorSettings.autoZoomEnabled = zoomEnabled }
        if let zoomLevel = state.autoZoomLevel { cursorSettings.autoZoomLevel = CGFloat(zoomLevel) }
        if let zoomSens = state.autoZoomSensitivity, let s = AutoZoomSensitivity(rawValue: zoomSens) { cursorSettings.autoZoomSensitivity = s }

        // Restore zoom regions
        if let savedRegions = state.zoomRegions {
            zoomRegions = savedRegions.compactMap { saved in
                guard let uuid = UUID(uuidString: saved.id) else { return nil }
                return ZoomRegion(
                    id: uuid,
                    startTime: saved.startTime,
                    endTime: saved.endTime,
                    zoomLevel: CGFloat(saved.zoomLevel),
                    focusX: saved.focusX,
                    focusY: saved.focusY,
                    isEnabled: saved.isEnabled
                )
            }
        }

        // Restore video: try bookmark first, fall back to stored path
        var url: URL?
        if let bookmark = state.sourceURLBookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                _ = resolved.startAccessingSecurityScopedResource()
                url = resolved
                logger.warning("loadProject: resolved via security-scoped bookmark → \(resolved.path)")
            } else if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                url = resolved
                logger.warning("loadProject: resolved via regular bookmark → \(resolved.path)")
            }
        }
        // Fallback: use stored file path directly
        if url == nil, let path = state.sourceURLPath {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                url = fileURL
                logger.warning("loadProject: resolved via stored path fallback → \(path)")
            }
        }
        guard let url else {
            logger.error("loadProject: FAILED — no bookmark and no valid path")
            currentProjectID = nil
            return
        }

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

                self.splitPoints = state.splitPoints
                self.segments = state.segmentStates.map {
                    Segment(startTime: $0.startTime, endTime: $0.endTime, speed: $0.speed, isEnabled: $0.isEnabled)
                }

                if self.segments.isEmpty {
                    self.segments = [Segment(startTime: 0, endTime: dur.seconds, speed: 1.0, isEnabled: true)]
                }

                // Load cursor metadata if available
                if let projectID = self.currentProjectID, let store = self.store {
                    let cursorMetaURL = store.projectDirectory(for: projectID).appendingPathComponent("recording.cursor.json")
                    if FileManager.default.fileExists(atPath: cursorMetaURL.path) {
                        self.cursorMetadataURL = cursorMetaURL
                        self.loadCursorMetadata()
                    }
                }

                self.rebuildPlayer()
                self.generateThumbnails()

                if state.playheadTime > 0 {
                    self.playheadTime = state.playheadTime
                    self.currentTime = state.playheadTime
                    let target = CMTime(seconds: state.playheadTime, preferredTimescale: 600)
                    await self.player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                }

                self.onVideoLoaded?(info.id, size, dur.seconds)
            } catch {
                print("Failed to restore video: \(error)")
            }
        }

        store.touchLastOpened(info.id)
    }

    func createProject(url: URL, store: ProjectStore) {
        self.store = store
        let projectID = UUID()
        self.currentProjectID = projectID

        let info = ProjectInfo(
            id: projectID,
            name: url.deletingPathExtension().lastPathComponent,
            sourceFileName: url.lastPathComponent
        )
        store.add(info)
        loadVideo(url: url)
    }

    func createProject(session: RecordingSession, store: ProjectStore) {
        self.store = store
        let projectID = UUID()
        self.currentProjectID = projectID

        let info = ProjectInfo(
            id: projectID,
            name: session.displayName
        )
        store.add(info)
        loadRecording(session: session)
    }

    // MARK: - Close Project

    func closeProject() {
        // Save state before clearing
        writeStateNow()

        // Generate thumbnail (capture refs before clearing)
        if let projectID = currentProjectID, let store, let capturedAsset = asset {
            let dur = duration
            let thumbnailURL = store.thumbnailURL(for: projectID)
            Task.detached {
                let time = CMTime(seconds: dur.seconds * 0.33, preferredTimescale: 600)
                let generator = AVAssetImageGenerator(asset: capturedAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 600, height: 400)

                guard let result = try? await generator.image(at: time) else { return }
                let nsImage = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }

                try? FileManager.default.createDirectory(at: thumbnailURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? jpegData.write(to: thumbnailURL, options: .atomic)
            }
        }

        // Tear down observers and player
        if let token = timeObserver, let player {
            player.removeTimeObserver(token)
            timeObserver = nil
        }
        if let token = boundaryObserver, let player {
            player.removeTimeObserver(token)
            boundaryObserver = nil
        }
        cancelSpeedRamp()

        player?.pause()
        player = nil
        playerItem = nil

        if let url = sourceURL {
            url.stopAccessingSecurityScopedResource()
        }

        sourceURL = nil
        asset = nil
        videoSize = .zero
        duration = .zero
        splitPoints = []
        segments = []
        selectedSegmentId = nil
        currentTime = 0
        playheadTime = 0
        isPlaying = false
        thumbnails = []
        cursorMetadataURL = nil
        recordingSession = nil
        cursorMetadata = nil
        cursorOverlayState = nil
        cursorSettings = CursorSettings()
        zoomRegions = []
        selectedZoomRegionID = nil
        undoStack = []
        redoStack = []
        currentProjectID = nil
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

                if let projectID = self.currentProjectID {
                    self.onVideoLoaded?(projectID, size, dur.seconds)
                }
            } catch {
                print("Failed to load video: \(error)")
            }
        }
    }

    // MARK: - Load Recording

    func loadRecording(session: RecordingSession) {
        // Copy recording from temp to project directory so it persists
        var videoURL = session.videoURL
        if let projectID = currentProjectID, let store {
            let projectDir = store.projectDirectory(for: projectID)
            let destURL = projectDir.appendingPathComponent("recording.mp4")
            try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            if (try? FileManager.default.copyItem(at: session.videoURL, to: destURL)) != nil {
                videoURL = destURL
            }

            // Copy cursor metadata alongside video
            if let cursorURL = session.cursorMetadataURL {
                let destCursorURL = projectDir.appendingPathComponent("recording.cursor.json")
                try? FileManager.default.copyItem(at: cursorURL, to: destCursorURL)
                self.cursorMetadataURL = destCursorURL
            }
        } else {
            self.cursorMetadataURL = session.cursorMetadataURL
        }

        let loadedAsset = AVAsset(url: videoURL)
        self.sourceURL = videoURL
        self.asset = loadedAsset
        self.recordingSession = session

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
                self.loadCursorMetadata()
                self.rebuildPlayer()
                self.generateThumbnails()
                self.saveState()

                if let projectID = self.currentProjectID {
                    self.onVideoLoaded?(projectID, size, dur.seconds)
                }
            } catch {
                print("Failed to load recording: \(error)")
            }
        }
    }

    // MARK: - Cursor Intelligence

    func loadCursorMetadata() {
        guard let url = cursorMetadataURL else {
            cursorMetadata = nil
            cursorOverlayState = nil
            return
        }
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(CursorMetadataFile.self, from: data) else {
            logger.warning("loadCursorMetadata: failed to decode \(url.path)")
            cursorMetadata = nil
            cursorOverlayState = nil
            return
        }
        cursorMetadata = metadata
        logger.warning("loadCursorMetadata: loaded \(metadata.events.count) events")
        rebuildCursorOverlay()
    }

    func rebuildCursorOverlay() {
        guard let metadata = cursorMetadata, cursorSettings.isEnabled else {
            cursorOverlayState = nil
            return
        }
        let frameRate: Double
        if let track = asset?.tracks(withMediaType: .video).first {
            frameRate = Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
        } else {
            frameRate = 30
        }
        cursorOverlayState = CursorOverlayEngine.prepare(
            metadata: metadata,
            settings: cursorSettings,
            outputFrameRate: frameRate,
            zoomRegions: zoomRegions
        )
    }

    func generateAutoZoomRegions() {
        guard let metadata = cursorMetadata else { return }
        let (clicks, keyInteractions, sourceSize) = CursorOverlayEngine.extractInteractions(from: metadata)
        zoomRegions = CursorOverlayEngine.generateZoomRegions(
            clicks: clicks,
            keyInteractions: keyInteractions,
            sensitivity: cursorSettings.autoZoomSensitivity,
            zoomLevel: cursorSettings.autoZoomLevel,
            sourceSize: sourceSize
        )
        selectedZoomRegionID = nil
        rebuildCursorOverlay()
        updateVisuals()
    }

    func deleteZoomRegion(_ id: UUID) {
        zoomRegions.removeAll { $0.id == id }
        if selectedZoomRegionID == id { selectedZoomRegionID = nil }
        rebuildCursorOverlay()
        updateVisuals()
    }

    func toggleZoomRegion(_ id: UUID) {
        guard let idx = zoomRegions.firstIndex(where: { $0.id == id }) else { return }
        zoomRegions[idx].isEnabled.toggle()
        rebuildCursorOverlay()
        updateVisuals()
    }

    func setZoomRegionLevel(_ level: CGFloat, for id: UUID) {
        guard let idx = zoomRegions.firstIndex(where: { $0.id == id }) else { return }
        zoomRegions[idx].zoomLevel = max(1.1, min(4.0, level))
        rebuildCursorOverlay()
        updateVisuals()
    }

    func setZoomRegionFocus(x: Double, y: Double, for id: UUID) {
        guard let idx = zoomRegions.firstIndex(where: { $0.id == id }) else { return }
        // Clamp focus so zoom crop stays within video bounds
        let zoom = zoomRegions[idx].zoomLevel
        let halfW = (videoSize.width / zoom) / 2
        let halfH = (videoSize.height / zoom) / 2
        zoomRegions[idx].focusX = max(halfW, min(videoSize.width - halfW, x))
        zoomRegions[idx].focusY = max(halfH, min(videoSize.height - halfH, y))
        rebuildCursorOverlay()
        updateVisuals()
    }

    /// Seek to a zoom region's start time so the preview shows the zoom effect
    func seekToZoomRegion(_ id: UUID) {
        guard let region = zoomRegions.first(where: { $0.id == id }) else { return }
        let time = region.startTime
        playheadTime = time
        currentTime = time
        seek(toFraction: time / duration.seconds)
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
            settings: renderSettings,
            cursorOverlayState: cursorOverlayState
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
            settings: renderSettings,
            cursorOverlayState: cursorOverlayState
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

        // Build cursor state remapped to composition timeline for export
        var exportCursorState: CursorOverlayState?
        if let cursorState = cursorOverlayState {
            let remapTable = CompositionEngine.buildTimeRemapTable(segments: enabledSegments)
            exportCursorState = CursorOverlayEngine.remapForExport(state: cursorState, remapTable: remapTable)
        }

        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: videoSize,
            settings: renderSettings,
            cursorOverlayState: exportCursorState
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
