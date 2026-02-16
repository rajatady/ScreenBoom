import SwiftUI
import AVFoundation

struct TimelineView: View {
    @Bindable var project: Project
    @State private var timelineZoom: CGFloat = 1.0
    @State private var hoverFraction: CGFloat?
    private let splitGap: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            segmentControlsBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            GeometryReader { geo in
                let baseWidth = geo.size.width
                let zoomedWidth = baseWidth * timelineZoom

                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .leading) {
                        if project.showThumbnails {
                            thumbnailStrip(width: zoomedWidth)
                                .mask(segmentShapes(width: zoomedWidth))
                        }
                        segmentOverlays(width: zoomedWidth)
                        hoverIndicator(width: zoomedWidth)
                        playhead(width: zoomedWidth)
                    }
                    .frame(width: zoomedWidth, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleTimelineInteraction(x: value.location.x, width: zoomedWidth)
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
                        case .ended:
                            hoverFraction = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Divider()

            playbackControls
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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

        // Select the segment at this source time
        if let seg = project.segments.first(where: { sourceTime >= $0.startTime && sourceTime < $0.endTime })
            ?? project.segments.last {
            project.selectedSegmentId = seg.id
        }

        // Commit playhead and current time immediately, then seek
        project.playheadTime = sourceTime
        project.currentTime = sourceTime
        project.seek(toFraction: fraction)
    }

    // MARK: - Segment Controls Bar

    var segmentControlsBar: some View {
        HStack(spacing: 12) {
            Button("Split") {
                project.addSplit(at: project.playheadTime)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let selectedId = project.selectedSegmentId,
               let seg = project.segments.first(where: { $0.id == selectedId }) {
                Divider().frame(height: 20)

                Button(seg.isEnabled ? "Disable" : "Enable") {
                    project.toggleSegment(selectedId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                HStack(spacing: 4) {
                    Text("Speed:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
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
                    .frame(width: 80)
                }

                if let splitIdx = splitIndexForSegment(selectedId) {
                    Button("Remove Split") {
                        project.removeSplit(at: splitIdx)
                        project.selectedSegmentId = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Spacer()

            // View toggle
            Button(action: { project.showThumbnails.toggle(); project.saveState() }) {
                Image(systemName: project.showThumbnails ? "photo.fill" : "rectangle.fill")
            }
            .buttonStyle(.borderless)
            .help(project.showThumbnails ? "Solid view" : "Frame view")

            // Zoom controls
            HStack(spacing: 6) {
                Button(action: { timelineZoom = max(1, timelineZoom - 1) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(timelineZoom <= 1)

                Text("\(Int(timelineZoom))x")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)

                Button(action: { timelineZoom = min(20, timelineZoom + 1) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Slider(value: $timelineZoom, in: 1...20, step: 1)
                    .frame(width: 80)
            }

            Text(String(format: "%.1fs", project.totalOutputDuration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Thumbnail Strip

    func thumbnailStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if project.thumbnails.isEmpty {
                Rectangle()
                    .fill(Color(nsColor: .darkGray).opacity(0.3))
                    .frame(width: width, height: 80)
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
        .frame(height: 80)
    }

    // MARK: - Segment Overlays (visual only, no separate gestures)

    func segmentOverlays(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, seg in
                let frame = segmentVisualFrame(index: index, totalWidth: width)
                let isSelected = project.selectedSegmentId == seg.id
                let cr = min(6.0, frame.width / 3)

                ZStack {
                    // Solid color fill (always visible in solid mode, hidden behind thumbnails in frame mode)
                    if !project.showThumbnails {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(segmentFillColor(seg: seg, isSelected: isSelected))
                    }

                    // Selection tint (in thumbnail mode)
                    if project.showThumbnails && isSelected {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(Color.accentColor.opacity(0.2))
                    }

                    // Disabled overlay
                    if !seg.isEnabled {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(Color.black.opacity(project.showThumbnails ? 0.55 : 0))
                        Text("Disabled")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Speed badge
                    if seg.isEnabled && seg.speed != 1.0 {
                        VStack {
                            Spacer()
                            Text("\(String(format: "%.1f", seg.speed))x")
                                .font(.system(.caption2, design: .monospaced))
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.blue.opacity(0.75)))
                                .padding(.bottom, 4)
                        }
                    }

                    // Border — always visible, contrasting
                    RoundedRectangle(cornerRadius: cr)
                        .stroke(
                            isSelected ? Color.accentColor : Color.gray.opacity(0.5),
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
            return isSelected ? Color(white: 0.25) : Color(white: 0.15)
        }
        if isSelected {
            return Color.accentColor.opacity(0.3)
        }
        return Color(white: 0.22)
    }

    // MARK: - Segment Shapes (mask for thumbnails + gap creation)

    func segmentShapes(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, _ in
                let frame = segmentVisualFrame(index: index, totalWidth: width)
                let cr = min(6.0, frame.width / 3)
                RoundedRectangle(cornerRadius: cr)
                    .fill(Color.white)
                    .frame(width: frame.width, height: 80)
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
    func hoverIndicator(width: CGFloat) -> some View {
        if let fraction = hoverFraction {
            let x = fraction * width
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 1, height: 90)
                .offset(x: max(0, min(width - 1, x)))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Playhead

    func playhead(width: CGFloat) -> some View {
        let dur = project.duration.seconds
        let fraction = dur > 0 ? project.playheadTime / dur : 0
        let x = fraction * width

        return Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: 86)
            .shadow(color: .red.opacity(0.5), radius: 4)
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

            let dur = project.duration.seconds
            let current = min(project.currentTime, dur)
            Text("\(formatTime(current)) / \(formatTime(dur))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()
        }
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
