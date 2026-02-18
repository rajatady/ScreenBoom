import SwiftUI
import AVFoundation

struct TimelineView: View {
    @Bindable var project: Project
    @State private var timelineZoom: CGFloat = 1.0
    @State private var hoverFraction: CGFloat?
    @State private var activeZoomDrag: ZoomDrag?
    @State private var isShowingResizeCursor = false
    @State private var zoomTrackHoverTime: Double?
    private let splitGap: CGFloat = 4

    private let zoomTrackHeight: CGFloat = SB.Layout.zoomTrackHeight
    private let edgeHitZone: CGFloat = 12

    private struct ZoomDrag: Equatable {
        enum Mode: Equatable { case resizeStart, resizeEnd, move }
        var regionID: UUID
        var mode: Mode
        var grabOffset: Double      // move: time from region start to grab point
        var originalDuration: Double // move: preserve region duration
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentControlsBar
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.xs + 2) // sb-exempt — micro-adjust for native controls

            Divider()

            GeometryReader { geo in
                let baseWidth = geo.size.width
                let zoomedWidth = baseWidth * timelineZoom

                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        if project.showThumbnails {
                            thumbnailStrip(width: zoomedWidth)
                                .mask(segmentShapes(width: zoomedWidth))
                        }
                        segmentOverlays(width: zoomedWidth)

                        // Zoom track pinned to bottom (always visible when cursor data exists)
                        if project.hasCursorData {
                            zoomTrack(width: zoomedWidth)
                                .frame(width: zoomedWidth, height: zoomTrackHeight)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }

                        hoverIndicator(width: zoomedWidth, height: geo.size.height)
                        playhead(width: zoomedWidth, height: geo.size.height)
                    }
                    .frame(width: zoomedWidth, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if activeZoomDrag != nil {
                                    // Ongoing zoom drag — continue regardless of Y
                                    handleZoomDragContinue(x: value.location.x, width: zoomedWidth)
                                } else {
                                    let y = value.location.y
                                    let zoomTrackTop = geo.size.height - zoomTrackHeight
                                    if project.hasCursorData && y >= zoomTrackTop {
                                        handleZoomDragStart(x: value.location.x, width: zoomedWidth)
                                    } else {
                                        handleTimelineInteraction(x: value.location.x, width: zoomedWidth)
                                    }
                                }
                            }
                            .onEnded { _ in
                                activeZoomDrag = nil
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let dur = project.duration.seconds
                            guard dur > 0 else { return }
                            let fraction = max(0, min(1, location.x / zoomedWidth))
                            hoverFraction = fraction
                            if !project.isPlaying {
                                project.currentTime = fraction * dur
                                project.seek(toFraction: fraction)
                            }

                            // Zoom track hover: "+" indicator on empty areas
                            let zoomTrackTop = geo.size.height - zoomTrackHeight
                            let inZoomTrack = project.hasCursorData && location.y >= zoomTrackTop
                            if inZoomTrack {
                                let time = fraction * dur
                                let overRegion = project.zoomRegions.contains { time >= $0.startTime && time <= $0.endTime }
                                zoomTrackHoverTime = overRegion ? nil : time
                            } else {
                                zoomTrackHoverTime = nil
                            }

                            // Resize cursor when hovering near zoom region edges
                            let nearEdge = inZoomTrack && !project.zoomRegions.isEmpty && isNearZoomRegionEdge(x: location.x, width: zoomedWidth, duration: dur)
                            if nearEdge && !isShowingResizeCursor {
                                NSCursor.resizeLeftRight.push()
                                isShowingResizeCursor = true
                            } else if !nearEdge && isShowingResizeCursor {
                                NSCursor.pop()
                                isShowingResizeCursor = false
                            }

                        case .ended:
                            hoverFraction = nil
                            zoomTrackHoverTime = nil
                            if isShowingResizeCursor {
                                NSCursor.pop()
                                isShowingResizeCursor = false
                            }
                        }
                    }
                    .contextMenu {
                        if project.hasCursorData {
                            if let id = project.selectedZoomRegionID,
                               let region = project.zoomRegions.first(where: { $0.id == id }) {
                                Button(region.isEnabled ? "Disable Zoom" : "Enable Zoom") {
                                    project.toggleZoomRegion(id)
                                }
                                Menu("Zoom Level") {
                                    ForEach([1.5, 2.0, 2.5, 3.0, 3.5, 4.0], id: \.self) { level in
                                        Button(String(format: "%.1fx", level)) {
                                            project.setZoomRegionLevel(CGFloat(level), for: id)
                                        }
                                    }
                                }
                                Button("Duplicate") {
                                    project.duplicateZoomRegion(id)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    project.deleteZoomRegion(id)
                                }
                                Divider()
                            }
                            Button("Add Zoom Region Here") {
                                project.addZoomRegion(at: project.playheadTime)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SB.Space.md)

            Divider()

            playbackControls
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.xs + 2) // sb-exempt — micro-adjust for native controls
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Unified timeline interaction

    /// Every click/drag on the timeline does two things:
    /// 1. Seeks the video to that position
    /// 2. Selects the segment under the cursor
    func handleTimelineInteraction(x: CGFloat, width: CGFloat) {
        let dur = project.duration.seconds
        guard dur > 0 else { return }

        let fraction = max(0, min(1, x / width))
        let sourceTime = fraction * dur

        // Select the segment at this source time, deselect zoom region
        if let seg = project.segments.first(where: { sourceTime >= $0.startTime && sourceTime < $0.endTime })
            ?? project.segments.last {
            project.selectedSegmentId = seg.id
        }
        project.selectedZoomRegionID = nil

        // Commit playhead and current time immediately, then seek
        project.playheadTime = sourceTime
        project.currentTime = sourceTime
        project.seek(toFraction: fraction)
    }

    // MARK: - Zoom Region Drag (resize edges / move)

    func handleZoomDragStart(x: CGFloat, width: CGFloat) {
        let dur = project.duration.seconds
        guard dur > 0 else { return }

        let sourceTime = max(0, min(dur, (x / width) * dur))

        for region in project.zoomRegions {
            let startX = (region.startTime / dur) * width
            let endX = (region.endTime / dur) * width

            // Near left edge → resize start
            if abs(x - startX) < edgeHitZone && x < endX {
                project.selectedZoomRegionID = region.id
                project.selectedSegmentId = nil
                activeZoomDrag = ZoomDrag(
                    regionID: region.id, mode: .resizeStart,
                    grabOffset: 0, originalDuration: region.endTime - region.startTime
                )
                return
            }

            // Near right edge → resize end
            if abs(x - endX) < edgeHitZone && x > startX {
                project.selectedZoomRegionID = region.id
                project.selectedSegmentId = nil
                activeZoomDrag = ZoomDrag(
                    regionID: region.id, mode: .resizeEnd,
                    grabOffset: 0, originalDuration: region.endTime - region.startTime
                )
                return
            }

            // Inside region → move
            if x > startX && x < endX {
                project.selectedZoomRegionID = region.id
                project.selectedSegmentId = nil
                activeZoomDrag = ZoomDrag(
                    regionID: region.id, mode: .move,
                    grabOffset: sourceTime - region.startTime,
                    originalDuration: region.endTime - region.startTime
                )
                // Seek to peak for preview
                let peakTime = (region.startTime + region.endTime) / 2
                project.playheadTime = peakTime
                project.currentTime = peakTime
                project.seek(toFraction: peakTime / dur)
                return
            }
        }

        // Clicked empty area on zoom track — add a new zoom region
        project.addZoomRegion(at: sourceTime)
    }

    func handleZoomDragContinue(x: CGFloat, width: CGFloat) {
        guard let drag = activeZoomDrag else { return }
        let dur = project.duration.seconds
        guard dur > 0 else { return }

        let sourceTime = max(0, min(dur, (x / width) * dur))

        switch drag.mode {
        case .resizeStart:
            guard let region = project.zoomRegions.first(where: { $0.id == drag.regionID }) else { return }
            project.setZoomRegionTimes(start: sourceTime, end: region.endTime, for: drag.regionID)

        case .resizeEnd:
            guard let region = project.zoomRegions.first(where: { $0.id == drag.regionID }) else { return }
            project.setZoomRegionTimes(start: region.startTime, end: sourceTime, for: drag.regionID)

        case .move:
            var newStart = sourceTime - drag.grabOffset
            var newEnd = newStart + drag.originalDuration
            // Clamp to video bounds while preserving duration
            if newStart < 0 { newStart = 0; newEnd = drag.originalDuration }
            if newEnd > dur { newEnd = dur; newStart = dur - drag.originalDuration }
            project.setZoomRegionTimes(start: newStart, end: newEnd, for: drag.regionID)
        }
    }

    // MARK: - Segment Controls Bar

    var segmentControlsBar: some View {
        HStack(spacing: SB.Space.md) {
            Button("Split") {
                project.addSplit(at: project.playheadTime)
            }
            .font(SB.Typo.captionMedium)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("timeline_split_button")

            if let selectedId = project.selectedSegmentId,
               let seg = project.segments.first(where: { $0.id == selectedId }) {
                Divider().frame(height: 20)

                Button(seg.isEnabled ? "Disable" : "Enable") {
                    project.toggleSegment(selectedId)
                }
                .font(SB.Typo.captionMedium)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("timeline_toggle_button")

                HStack(spacing: SB.Space.xs) {
                    Text("Speed:")
                        .font(SB.Typo.caption)
                        .foregroundStyle(SB.Colors.textSecondary)
                    Picker("Speed", selection: Binding(
                        get: { seg.speed },
                        set: { project.setSpeed($0, for: selectedId) }
                    )) {
                        Text("0.25x").tag(0.25)
                        Text("0.5x").tag(0.5)
                        Text("0.75x").tag(0.75)
                        Text("1x").tag(1.0)
                        Text("1.2x").tag(1.2)
                        Text("1.4x").tag(1.4)
                        Text("1.6x").tag(1.6)
                        Text("1.8x").tag(1.8)
                        Text("2x").tag(2.0)
                        Text("3x").tag(3.0)
                        Text("4x").tag(4.0)
                        Text("6x").tag(6.0)
                        Text("8x").tag(8.0)
                        Text("16x").tag(16.0)
                        Text("24x").tag(24.0)
                        Text("32x").tag(32.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: SB.Layout.speedPickerWidth)
                    .accessibilityIdentifier("timeline_speed_picker")
                }

                if let splitIdx = splitIndexForSegment(selectedId) {
                    Button("Remove Split") {
                        project.removeSplit(at: splitIdx)
                        project.selectedSegmentId = nil
                    }
                    .font(SB.Typo.captionMedium)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("timeline_remove_split_button")
                }
            }

            Spacer()

            // View toggle
            Button(action: { project.showThumbnails.toggle(); project.saveState() }) {
                Image(systemName: project.showThumbnails ? "photo.fill" : "rectangle.fill")
            }
            .buttonStyle(.borderless)
            .help(project.showThumbnails ? "Solid view" : "Frame view")

            // Timeline zoom controls
            HStack(spacing: SB.Space.xs + 2) {
                Button(action: { timelineZoom = max(1, timelineZoom - 1) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(timelineZoom <= 1)

                Text("\(Int(timelineZoom))x")
                    .font(SB.Typo.mono)
                    .foregroundStyle(SB.Colors.textSecondary)
                    .frame(width: 30)

                Button(action: { timelineZoom = min(20, timelineZoom + 1) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Slider(value: $timelineZoom, in: 1...20, step: 1)
                    .frame(width: 80)
            }

            Text(String(format: "%.1fs", project.totalOutputDuration))
                .font(SB.Typo.mono)
                .foregroundStyle(SB.Colors.textSecondary)
                .accessibilityIdentifier("timeline_total_duration")
        }
    }

    // MARK: - Thumbnail Strip

    func thumbnailStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if project.thumbnails.isEmpty {
                Rectangle()
                    .fill(SB.Colors.surface.opacity(0.3))
                    .frame(width: width, height: SB.Layout.segmentTrackHeight)
            } else {
                let thumbWidth = width / CGFloat(project.thumbnails.count)
                ForEach(Array(project.thumbnails.enumerated()), id: \.offset) { _, cgImage in
                    Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 120)))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbWidth, height: 80)
                        .clipped()
                }
            }
        }
        .frame(height: SB.Layout.segmentTrackHeight)
    }

    // MARK: - Segment Overlays (visual only, no separate gestures)

    func segmentOverlays(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, seg in
                let frame = segmentVisualFrame(index: index, totalWidth: width)
                let isSelected = project.selectedSegmentId == seg.id
                let cr = min(SB.Radius.sm, frame.width / 3) // sb-exempt — dynamic clamped radius

                ZStack {
                    // Solid color fill (always visible in solid mode, hidden behind thumbnails in frame mode)
                    if !project.showThumbnails {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(segmentFillColor(seg: seg, isSelected: isSelected))
                    }

                    // Selection tint (in thumbnail mode)
                    if project.showThumbnails && isSelected {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(SB.Colors.accent.opacity(0.2))
                    }

                    // Disabled overlay
                    if !seg.isEnabled {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(SB.Colors.surfaceOverlay.opacity(project.showThumbnails ? 1.1 : 0))
                        Text("Disabled")
                            .font(SB.Typo.caption)
                            .foregroundStyle(SB.Colors.textSecondary)
                    }

                    // Speed badge
                    if seg.isEnabled && seg.speed != 1.0 {
                        VStack {
                            Spacer()
                            Text("\(String(format: "%.1f", seg.speed))x")
                                .font(SB.Typo.mono)
                                .bold()
                                .foregroundStyle(SB.Colors.textPrimary)
                                .padding(.horizontal, SB.Space.xs + 1)
                                .padding(.vertical, SB.Space.xxs)
                                .background(Capsule().fill(SB.Colors.accent.opacity(0.75)))
                                .padding(.bottom, SB.Space.xs)
                        }
                    }

                    // Border — always visible, contrasting
                    RoundedRectangle(cornerRadius: cr)
                        .stroke(
                            isSelected ? SB.Colors.accent : SB.Colors.textTertiary.opacity(0.5),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .frame(width: frame.width, height: 80)
                .offset(x: frame.x)
                .allowsHitTesting(false)
            }
        }
    }

    private func segmentFillColor(seg: Segment, isSelected: Bool) -> Color {
        if !seg.isEnabled {
            return isSelected ? SB.Colors.surfaceRaised : SB.Colors.surface
        }
        if isSelected {
            return SB.Colors.accent.opacity(0.3)
        }
        return SB.Colors.surfaceHover.opacity(0.85)
    }

    // MARK: - Segment Shapes (mask for thumbnails + gap creation)

    func segmentShapes(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Invisible spacer to anchor the ZStack at full width —
            // without this, .offset() children make the ZStack narrower
            // than the thumbnail strip, causing the mask to mis-center.
            Color.clear.frame(width: width, height: SB.Layout.segmentTrackHeight) // sb-exempt

            ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, _ in
                let frame = segmentVisualFrame(index: index, totalWidth: width)
                let cr = min(SB.Radius.sm, frame.width / 3) // sb-exempt — dynamic clamped radius
                RoundedRectangle(cornerRadius: cr)
                    .fill(.white) // sb-exempt — SwiftUI mask fill (not displayed)
                    .frame(width: frame.width, height: SB.Layout.segmentTrackHeight)
                    .offset(x: frame.x)
            }
        }
    }

    private func segmentVisualFrame(index: Int, totalWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let seg = project.segments[index]
        let dur = project.duration.seconds
        guard dur > 0 else { return (0, totalWidth) }

        let halfGap = splitGap / 2
        let rawX = (seg.startTime / dur) * totalWidth
        let rawW = (seg.duration / dur) * totalWidth

        let leftInset: CGFloat = index > 0 ? halfGap : 0
        let rightInset: CGFloat = index < project.segments.count - 1 ? halfGap : 0

        return (x: rawX + leftInset, width: max(2, rawW - leftInset - rightInset))
    }

    // MARK: - Playhead

    // MARK: - Hover Indicator

    @ViewBuilder
    func hoverIndicator(width: CGFloat, height: CGFloat) -> some View {
        if let fraction = hoverFraction {
            let x = fraction * width
            Rectangle()
                .fill(SB.Glass.strong) // sb-exempt — hover line
                .frame(width: 1, height: height + 10)
                .offset(x: max(0, min(width - 1, x)))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Playhead

    func playhead(width: CGFloat, height: CGFloat) -> some View {
        let dur = project.duration.seconds
        let fraction = dur > 0 ? project.playheadTime / dur : 0
        let x = fraction * width

        return Rectangle()
            .fill(SB.Colors.playhead)
            .frame(width: 2, height: height + 6)
            .sbShadow(SB.Shadows.playhead)
            .offset(x: max(0, min(width - 2, x)) - 1)
            .allowsHitTesting(false)
    }

    // MARK: - Playback Controls

    var playbackControls: some View {
        HStack {
            Button(action: { project.togglePlayback() }) {
                Image(systemName: project.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("timeline_play_button")

            let dur = project.duration.seconds
            let current = min(project.currentTime, dur)
            Text("\(formatTime(current)) / \(formatTime(dur))")
                .font(SB.Typo.mono)
                .foregroundStyle(SB.Colors.textSecondary)

            Spacer()
        }
    }

    // MARK: - Zoom Track

    func zoomTrack(width: CGFloat) -> some View {
        let dur = project.duration.seconds

        return ZStack(alignment: .leading) {
            // Baseline
            VStack {
                Spacer()
                Rectangle()
                    .fill(SB.Colors.border)
                    .frame(height: 1)
            }

            // Zoom regions as trapezoid shapes
            if dur > 0 {
                ForEach(project.zoomRegions) { region in
                    zoomRegionShape(region: region, totalWidth: width, duration: dur)
                }

                // Ghost "+" indicator on hover over empty areas
                if let hoverTime = zoomTrackHoverTime {
                    let ghostDuration: Double = 2.0
                    let ghostWidth = max(40, width * (ghostDuration / dur))
                    let hoverX = (hoverTime / dur) * width
                    let ghostStartX = max(0, min(width - ghostWidth, hoverX - ghostWidth / 2))
                    let ghostHeight = zoomTrackHeight * 0.45

                    ZStack {
                        RoundedRectangle(cornerRadius: SB.Radius.xs)
                            .fill(SB.Colors.accent.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: SB.Radius.xs)
                                    .stroke(SB.Colors.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                        Image(systemName: "plus")
                            .font(SB.Icons.sm)
                            .foregroundStyle(SB.Colors.accent.opacity(0.6))
                    }
                    .frame(width: ghostWidth, height: ghostHeight)
                    .offset(x: ghostStartX, y: (zoomTrackHeight - ghostHeight) / 2 - 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(SB.Anim.fadeQuick, value: zoomTrackHoverTime != nil)
                }
            }
        }
        .padding(.top, SB.Space.xxs)
    }

    private func zoomRegionShape(region: ZoomRegion, totalWidth: CGFloat, duration: Double) -> some View {
        let isSelected = project.selectedZoomRegionID == region.id
        let sensitivity = project.cursorSettings.autoZoomSensitivity

        let startX = (region.startTime / duration) * totalWidth
        let endX = (region.endTime / duration) * totalWidth
        let regionWidth = max(4, endX - startX)

        // Ramp durations as proportion of region width
        let regionDuration = region.endTime - region.startTime
        let rampInFraction = regionDuration > 0.01 ? min(0.35, sensitivity.zoomInDuration / regionDuration) : 0.2
        let rampOutFraction = regionDuration > 0.01 ? min(0.35, sensitivity.zoomOutDuration / regionDuration) : 0.2

        // Peak height: half-height baseline at 1x, full height at 4x — always selectable
        let normalizedZoom = min(1.0, (region.zoomLevel - 1.0) / 3.0) // 1.0 -> 0, 4.0 -> 1.0
        let fraction = 0.5 + 0.5 * normalizedZoom  // 1.0x -> 50%, 4.0x -> 100%
        let peakHeight = zoomTrackHeight * 0.85 * fraction

        let fillColor = region.isEnabled
            ? (isSelected ? SB.Colors.accent.opacity(0.45) : SB.Colors.accent.opacity(0.25))
            : SB.Colors.textTertiary.opacity(0.2)
        let strokeColor = region.isEnabled
            ? (isSelected ? SB.Colors.accent : SB.Colors.accent.opacity(0.4))
            : SB.Colors.textTertiary.opacity(0.4)

        return ZStack {
            // Trapezoid shape
            TrapezoidShape(rampInFraction: rampInFraction, rampOutFraction: rampOutFraction)
                .fill(fillColor)
                .frame(width: regionWidth, height: peakHeight)

            TrapezoidShape(rampInFraction: rampInFraction, rampOutFraction: rampOutFraction)
                .stroke(strokeColor, style: region.isEnabled
                    ? StrokeStyle(lineWidth: isSelected ? 1.5 : 1)
                    : StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(width: regionWidth, height: peakHeight)

            // Zoom label at peak center
            if regionWidth > 30 {
                Text(String(format: "%.1fx", region.zoomLevel))
                    .font(SB.Typo.microMono)
                    .foregroundStyle(region.isEnabled ? SB.Colors.textSecondary : SB.Colors.textTertiary)
                    .offset(y: -2)
            }

            // Edge grab handles (visible on selected regions)
            if isSelected && peakHeight > 8 {
                HStack {
                    RoundedRectangle(cornerRadius: SB.Radius.xxs)
                        .fill(SB.Colors.accent)
                        .frame(width: 3, height: max(8, peakHeight * 0.5))
                        .sbShadow(SB.Shadows.glow(SB.Colors.accent))
                    Spacer()
                    RoundedRectangle(cornerRadius: SB.Radius.xxs)
                        .fill(SB.Colors.accent)
                        .frame(width: 3, height: max(8, peakHeight * 0.5))
                        .sbShadow(SB.Shadows.glow(SB.Colors.accent))
                }
                .frame(width: regionWidth)
            }
        }
        .frame(width: regionWidth, height: peakHeight)
        .offset(x: startX, y: (zoomTrackHeight - peakHeight) / 2 - 2)
        .allowsHitTesting(false) // hit testing handled by the track gesture
    }

    func isNearZoomRegionEdge(x: CGFloat, width: CGFloat, duration: Double) -> Bool {
        for region in project.zoomRegions {
            let startX = (region.startTime / duration) * width
            let endX = (region.endTime / duration) * width
            if abs(x - startX) < edgeHitZone || abs(x - endX) < edgeHitZone {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    func splitIndexForSegment(_ segmentId: UUID) -> Int? {
        guard let seg = project.segments.first(where: { $0.id == segmentId }) else { return nil }
        return project.splitPoints.firstIndex(where: { abs($0 - seg.startTime) < 0.02 })
            ?? project.splitPoints.firstIndex(where: { abs($0 - seg.endTime) < 0.02 })
    }

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

// MARK: - Trapezoid Shape (zoom region mountain)

struct TrapezoidShape: Shape {
    var rampInFraction: CGFloat
    var rampOutFraction: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let rampInW = rect.width * rampInFraction
        let rampOutW = rect.width * rampOutFraction

        // Start at bottom-left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Ramp up to peak
        path.addLine(to: CGPoint(x: rect.minX + rampInW, y: rect.minY))
        // Flat peak
        path.addLine(to: CGPoint(x: rect.maxX - rampOutW, y: rect.minY))
        // Ramp down
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}
