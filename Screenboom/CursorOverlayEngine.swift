import Foundation
import CoreImage
import AppKit
import os

private let zoomLog = Logger(subsystem: "com.trymagically.Screenboom", category: "AutoZoom")

// MARK: - Data Types

struct SmoothedCursorPoint: Sendable {
    var timestamp: Double
    var x: Double  // video coordinates (top-left origin)
    var y: Double
}

struct CursorClick: Sendable {
    var timestamp: Double
    var x: Double
    var y: Double
    var button: CursorEvent.Button
}

struct CursorSettings: Codable, Sendable {
    var isEnabled: Bool = true
    var style: CursorStyle = .arrow
    var size: CGFloat = 1.2
    var clickEffectEnabled: Bool = true
    var clickEffectColor: [Double] = [1.0, 0.35, 0.37]
    var clickEffectMaxRadius: CGFloat = 40
    var clickEffectDuration: Double = 0.4
    var autoZoomEnabled: Bool = false
    var autoZoomLevel: CGFloat = 1.3
    var autoZoomSensitivity: AutoZoomSensitivity = .balanced
}

enum CursorStyle: String, CaseIterable, Codable, Sendable {
    case arrow, pointer, crosshair, circleDot

    nonisolated var displayName: String {
        switch self {
        case .arrow: "Arrow"
        case .pointer: "Pointer"
        case .crosshair: "Cross"
        case .circleDot: "Dot"
        }
    }

    nonisolated static func fromDisplayName(_ name: String) -> CursorStyle {
        allCases.first { $0.displayName == name } ?? .arrow
    }
}

enum AutoZoomSensitivity: String, CaseIterable, Codable, Sendable {
    case subtle, balanced, dramatic

    nonisolated var displayName: String { rawValue.capitalized }

    nonisolated var clusterWindow: Double {
        switch self { case .subtle: 4.0; case .balanced: 3.0; case .dramatic: 2.0 }
    }
    nonisolated var minimumClusterSize: Int {
        switch self { case .subtle: 3; case .balanced: 2; case .dramatic: 1 }
    }
    nonisolated var holdDuration: Double {
        switch self { case .subtle: 1.0; case .balanced: 1.5; case .dramatic: 2.5 }
    }
    nonisolated var zoomInDuration: Double {
        switch self { case .subtle: 0.8; case .balanced: 0.5; case .dramatic: 0.3 }
    }
    nonisolated var zoomOutDuration: Double {
        switch self { case .subtle: 1.0; case .balanced: 0.8; case .dramatic: 0.5 }
    }
}

struct ZoomRegion: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var startTime: Double      // source time: zoom-in begins
    var endTime: Double        // source time: zoom-out completes
    var zoomLevel: CGFloat     // peak zoom (1.5–4.0x)
    var focusX: Double         // focus in source video coords (top-left)
    var focusY: Double
    var isEnabled: Bool = true
}

struct ZoomKeyframe: Sendable {
    var timestamp: Double
    var zoomLevel: CGFloat
    var focusPoint: CGPoint  // source video coordinates (top-left origin)
    var easingDuration: Double
}

/// Immutable pre-computed state for use inside CIFilter handler (arbitrary queue)
struct CursorOverlayState: @unchecked Sendable {
    let smoothedPoints: [SmoothedCursorPoint]
    let clicks: [CursorClick]
    let cursorCIImage: CIImage
    let cursorHotspot: CGPoint
    let sourceSize: CGSize
    let captureOrigin: CGPoint
    let settings: CursorSettings
    let zoomKeyframes: [ZoomKeyframe]
}

// MARK: - Time Remap Table (for export)

struct TimeRemapEntry: Sendable {
    var compositionTime: Double
    var sourceTime: Double
}

struct TimeRemapTable: Sendable {
    let entries: [TimeRemapEntry]

    nonisolated func sourceTime(forCompositionTime t: Double) -> Double {
        guard !entries.isEmpty else { return t }
        if t <= entries.first!.compositionTime { return entries.first!.sourceTime }
        if t >= entries.last!.compositionTime { return entries.last!.sourceTime }

        var lo = 0, hi = entries.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if entries[mid].compositionTime <= t { lo = mid } else { hi = mid }
        }

        let a = entries[lo], b = entries[hi]
        let range = b.compositionTime - a.compositionTime
        guard range > 0.0001 else { return a.sourceTime }
        let frac = (t - a.compositionTime) / range
        return a.sourceTime + frac * (b.sourceTime - a.sourceTime)
    }
}

// MARK: - Engine

enum CursorOverlayEngine {

    // MARK: - Prepare (call once when loading project or changing settings)

    nonisolated static func prepare(
        metadata: CursorMetadataFile,
        settings: CursorSettings,
        outputFrameRate: Double,
        zoomRegions: [ZoomRegion] = []
    ) -> CursorOverlayState {
        let sourceSize = CGSize(width: metadata.sourceSize.width, height: metadata.sourceSize.height)
        let captureOrigin: CGPoint
        if let origin = metadata.captureOrigin {
            captureOrigin = CGPoint(x: origin.x, y: origin.y)
        } else {
            captureOrigin = .zero
        }

        // Convert raw events to video coordinates (top-left origin)
        let moveEvents = metadata.events.filter { $0.type == .move || $0.type == .click }
        let videoPoints: [(timestamp: Double, x: Double, y: Double)] = moveEvents.map { event in
            let videoX = event.x - captureOrigin.x
            let videoY = sourceSize.height - (event.y - captureOrigin.y)
            return (event.timestamp, videoX, videoY)
        }

        // Extract clicks in video coordinates
        let clicks: [CursorClick] = metadata.events
            .filter { $0.type == .click }
            .compactMap { event in
                guard let button = event.button else { return nil }
                let videoX = event.x - captureOrigin.x
                let videoY = sourceSize.height - (event.y - captureOrigin.y)
                return CursorClick(timestamp: event.timestamp, x: videoX, y: videoY, button: button)
            }

        // Smooth positions
        let smoothed = smoothPositions(videoPoints, outputFrameRate: outputFrameRate)

        // Pre-render cursor image
        let (cursorImage, hotspot) = renderCursorImage(style: settings.style, size: settings.size)

        // Convert stored zoom regions to keyframes for the render pipeline
        let zoomKFs: [ZoomKeyframe]
        if settings.autoZoomEnabled && !zoomRegions.isEmpty {
            zoomKFs = self.zoomKeyframes(from: zoomRegions, sensitivity: settings.autoZoomSensitivity, sourceSize: sourceSize)
        } else {
            zoomKFs = []
        }

        return CursorOverlayState(
            smoothedPoints: smoothed,
            clicks: clicks,
            cursorCIImage: cursorImage,
            cursorHotspot: hotspot,
            sourceSize: sourceSize,
            captureOrigin: captureOrigin,
            settings: settings,
            zoomKeyframes: zoomKFs
        )
    }

    // MARK: - Per-frame cursor + click composite

    nonisolated static func cursorComposite(
        in state: CursorOverlayState,
        at timestamp: Double,
        recordingRect: CGRect,
        outputSize: CGSize,
        zoomCropRect: CGRect?
    ) -> CIImage? {
        guard state.settings.isEnabled else { return nil }

        let outputRect = CGRect(origin: .zero, size: outputSize)
        var result: CIImage?

        // Cursor position
        if let pos = lookupPosition(in: state.smoothedPoints, at: timestamp) {
            let outputPos = mapToOutput(
                cursorX: pos.x, cursorY: pos.y,
                sourceSize: state.sourceSize,
                recordingRect: recordingRect,
                zoomCropRect: zoomCropRect
            )

            // CIImage uses bottom-left origin
            let ciX = outputPos.x - state.cursorHotspot.x
            let ciY = (outputSize.height - outputPos.y) - (state.cursorCIImage.extent.height - state.cursorHotspot.y)

            let positioned = state.cursorCIImage
                .transformed(by: CGAffineTransform(translationX: ciX, y: ciY))
                .cropped(to: outputRect)

            result = positioned
        }

        // Click effects
        if state.settings.clickEffectEnabled {
            let clickImage = renderClickEffects(
                in: state, at: timestamp,
                recordingRect: recordingRect,
                outputSize: outputSize,
                zoomCropRect: zoomCropRect
            )
            if let clickImage {
                result = result.map { clickImage.composited(over: $0) } ?? clickImage
            }
        }

        return result
    }

    // MARK: - Auto-zoom crop rect

    nonisolated static func zoomCropRect(
        in state: CursorOverlayState,
        at timestamp: Double,
        sourceExtent: CGRect
    ) -> CGRect? {
        guard state.settings.autoZoomEnabled, !state.zoomKeyframes.isEmpty else { return nil }

        let (zoom, focus) = interpolateZoom(keyframes: state.zoomKeyframes, at: timestamp)
        guard zoom > 1.001 else { return nil }

        let cropW = sourceExtent.width / zoom
        let cropH = sourceExtent.height / zoom

        // Center on focus point, clamp to bounds
        // Focus is in video top-left coords, but CIImage uses bottom-left
        let ciFocusY = sourceExtent.height - focus.y
        var cropX = focus.x - cropW / 2
        var cropY = ciFocusY - cropH / 2

        cropX = max(sourceExtent.origin.x, min(sourceExtent.origin.x + sourceExtent.width - cropW, cropX))
        cropY = max(sourceExtent.origin.y, min(sourceExtent.origin.y + sourceExtent.height - cropH, cropY))

        return CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
    }

    // MARK: - Export remap

    nonisolated static func remapForExport(
        state: CursorOverlayState,
        remapTable: TimeRemapTable
    ) -> CursorOverlayState {
        // Re-sample smoothed points at composition time
        // Walk the remap entries and for each composition time, look up source time,
        // then look up cursor position at that source time
        let remappedPoints: [SmoothedCursorPoint] = remapTable.entries.map { entry in
            let sourceT = entry.sourceTime
            if let pos = lookupPosition(in: state.smoothedPoints, at: sourceT) {
                return SmoothedCursorPoint(timestamp: entry.compositionTime, x: pos.x, y: pos.y)
            }
            return SmoothedCursorPoint(timestamp: entry.compositionTime, x: 0, y: 0)
        }

        // Remap clicks
        let remappedClicks: [CursorClick] = state.clicks.compactMap { click in
            // Find composition time for this source click timestamp
            // Reverse lookup through remap table
            guard let compTime = compositionTime(forSourceTime: click.timestamp, in: remapTable) else { return nil }
            return CursorClick(timestamp: compTime, x: click.x, y: click.y, button: click.button)
        }

        // Remap zoom keyframes
        let remappedZoom: [ZoomKeyframe] = state.zoomKeyframes.compactMap { kf in
            guard let compTime = compositionTime(forSourceTime: kf.timestamp, in: remapTable) else { return nil }
            return ZoomKeyframe(timestamp: compTime, zoomLevel: kf.zoomLevel, focusPoint: kf.focusPoint, easingDuration: kf.easingDuration)
        }

        return CursorOverlayState(
            smoothedPoints: remappedPoints,
            clicks: remappedClicks,
            cursorCIImage: state.cursorCIImage,
            cursorHotspot: state.cursorHotspot,
            sourceSize: state.sourceSize,
            captureOrigin: state.captureOrigin,
            settings: state.settings,
            zoomKeyframes: remappedZoom
        )
    }

    // MARK: - Catmull-Rom Smoothing

    private nonisolated static func smoothPositions(
        _ points: [(timestamp: Double, x: Double, y: Double)],
        outputFrameRate: Double
    ) -> [SmoothedCursorPoint] {
        guard points.count >= 2 else {
            return points.map { SmoothedCursorPoint(timestamp: $0.timestamp, x: $0.x, y: $0.y) }
        }

        let totalDuration = points.last!.timestamp
        guard totalDuration > 0 else { return [] }

        let frameDuration = 1.0 / outputFrameRate
        var result: [SmoothedCursorPoint] = []

        var t = 0.0
        while t <= totalDuration {
            let pos = evaluateCatmullRom(points: points, at: t)
            result.append(SmoothedCursorPoint(timestamp: t, x: pos.x, y: pos.y))
            t += frameDuration
        }

        return result
    }

    private nonisolated static func evaluateCatmullRom(
        points: [(timestamp: Double, x: Double, y: Double)],
        at t: Double
    ) -> (x: Double, y: Double) {
        // Find bracketing index
        var idx = 0
        for i in 0..<points.count {
            if points[i].timestamp <= t { idx = i }
            else { break }
        }

        // Get 4 control points: p0, p1, p2, p3
        let i1 = idx
        let i0 = max(0, i1 - 1)
        let i2 = min(points.count - 1, i1 + 1)
        let i3 = min(points.count - 1, i2 + 1)

        let p0 = points[i0], p1 = points[i1], p2 = points[i2], p3 = points[i3]

        // Parameter within segment [p1, p2]
        let segDuration = p2.timestamp - p1.timestamp
        guard segDuration > 0.0001 else {
            return (p1.x, p1.y)
        }
        let u = min(1.0, max(0.0, (t - p1.timestamp) / segDuration))

        // Centripetal Catmull-Rom (alpha = 0.5)
        let alpha = 0.5

        func dist(_ a: (timestamp: Double, x: Double, y: Double),
                   _ b: (timestamp: Double, x: Double, y: Double)) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            return sqrt(dx * dx + dy * dy)
        }

        let d01 = pow(max(dist(p0, p1), 0.001), alpha)
        let d12 = pow(max(dist(p1, p2), 0.001), alpha)
        let d23 = pow(max(dist(p2, p3), 0.001), alpha)

        // Compute control points for cubic Bezier equivalent
        func controlPoint(
            pA: (x: Double, y: Double), pB: (x: Double, y: Double), pC: (x: Double, y: Double),
            dA: Double, dB: Double
        ) -> (x: Double, y: Double) {
            let dAB = dA + dB
            guard dAB > 0.001 else { return pB }
            let b1x = (dA * dA * pC.x - dB * dB * pA.x + (2 * dA * dA + 3 * dA * dB + dB * dB) * pB.x) / (3 * dA * dAB)
            let b1y = (dA * dA * pC.y - dB * dB * pA.y + (2 * dA * dA + 3 * dA * dB + dB * dB) * pB.y) / (3 * dA * dAB)
            return (b1x, b1y)
        }

        let cp1 = controlPoint(pA: (p0.x, p0.y), pB: (p1.x, p1.y), pC: (p2.x, p2.y), dA: d01, dB: d12)
        let cp2x: Double
        let cp2y: Double
        let d12_23 = d12 + d23
        if d12_23 > 0.001 {
            cp2x = (d23 * d23 * p1.x - d12 * d12 * p3.x + (2 * d23 * d23 + 3 * d23 * d12 + d12 * d12) * p2.x) / (3 * d23 * d12_23)
            cp2y = (d23 * d23 * p1.y - d12 * d12 * p3.y + (2 * d23 * d23 + 3 * d23 * d12 + d12 * d12) * p2.y) / (3 * d23 * d12_23)
        } else {
            cp2x = p2.x
            cp2y = p2.y
        }

        // Cubic Bezier evaluation
        let u2 = u * u, u3 = u2 * u
        let mu = 1 - u, mu2 = mu * mu, mu3 = mu2 * mu

        let x = mu3 * p1.x + 3 * mu2 * u * cp1.x + 3 * mu * u2 * cp2x + u3 * p2.x
        let y = mu3 * p1.y + 3 * mu2 * u * cp1.y + 3 * mu * u2 * cp2y + u3 * p2.y

        return (x, y)
    }

    // MARK: - Position Lookup (binary search)

    private nonisolated static func lookupPosition(
        in points: [SmoothedCursorPoint],
        at timestamp: Double
    ) -> (x: Double, y: Double)? {
        guard !points.isEmpty else { return nil }
        if timestamp <= points.first!.timestamp { return (points.first!.x, points.first!.y) }
        if timestamp >= points.last!.timestamp { return (points.last!.x, points.last!.y) }

        var lo = 0, hi = points.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if points[mid].timestamp <= timestamp { lo = mid } else { hi = mid }
        }

        let a = points[lo], b = points[hi]
        let range = b.timestamp - a.timestamp
        guard range > 0.0001 else { return (a.x, a.y) }
        let frac = (timestamp - a.timestamp) / range
        return (a.x + frac * (b.x - a.x), a.y + frac * (b.y - a.y))
    }

    // MARK: - Coordinate Mapping

    private nonisolated static func mapToOutput(
        cursorX: Double, cursorY: Double,
        sourceSize: CGSize,
        recordingRect: CGRect,
        zoomCropRect: CGRect?
    ) -> CGPoint {
        var cx = cursorX, cy = cursorY

        // If zoomed, adjust cursor position relative to zoom crop
        if let zoomRect = zoomCropRect {
            // zoomRect is in CIImage coords (bottom-left). Convert cursor to CIImage coords first.
            let ciCursorY = sourceSize.height - cy
            cx = (cx - zoomRect.origin.x) * (sourceSize.width / zoomRect.width)
            let adjustedCIY = (ciCursorY - zoomRect.origin.y) * (sourceSize.height / zoomRect.height)
            cy = sourceSize.height - adjustedCIY
        }

        // Map from source coords to recording rect within output
        let scaleX = recordingRect.width / sourceSize.width
        let scaleY = recordingRect.height / sourceSize.height
        let scale = min(scaleX, scaleY)

        let scaledW = sourceSize.width * scale
        let scaledH = sourceSize.height * scale
        let offsetX = recordingRect.midX - scaledW / 2
        let offsetY = recordingRect.midY - scaledH / 2

        let outputX = offsetX + cx * scale
        let outputY = offsetY + cy * scale

        return CGPoint(x: outputX, y: outputY)
    }

    // MARK: - Cursor Image Rendering

    private nonisolated static func renderCursorImage(
        style: CursorStyle,
        size: CGFloat
    ) -> (CIImage, CGPoint) {
        switch style {
        case .arrow:
            return renderSystemCursor(NSCursor.arrow, size: size)
        case .pointer:
            return renderSystemCursor(NSCursor.pointingHand, size: size)
        case .crosshair:
            return renderSystemCursor(NSCursor.crosshair, size: size)
        case .circleDot:
            return renderCircleDotCursor(size: size)
        }
    }

    private nonisolated static func renderSystemCursor(
        _ cursor: NSCursor,
        size: CGFloat
    ) -> (CIImage, CGPoint) {
        let image = cursor.image
        let hotspot = cursor.hotSpot

        let targetW = image.size.width * size
        let targetH = image.size.height * size

        let nsImage = NSImage(size: NSSize(width: targetW, height: targetH), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let fallback = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.8))
                .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
            return (fallback, CGPoint(x: 1, y: 1))
        }

        let scaledHotspot = CGPoint(x: hotspot.x * size, y: hotspot.y * size)
        return (CIImage(cgImage: cgImage), scaledHotspot)
    }

    private nonisolated static func renderCircleDotCursor(size: CGFloat) -> (CIImage, CGPoint) {
        let baseSize: CGFloat = 24
        let s = baseSize * size
        let center = s / 2

        guard let ctx = CGContext(
            data: nil, width: Int(s), height: Int(s),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            let fallback = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.8))
                .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
            return (fallback, CGPoint(x: 8, y: 8))
        }

        // Outer ring
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(2.0 * size)
        ctx.strokeEllipse(in: CGRect(x: 2, y: 2, width: s - 4, height: s - 4))

        // Center dot
        let dotR: CGFloat = 3 * size
        ctx.setFillColor(CGColor(red: 1, green: 0.35, blue: 0.37, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: center - dotR, y: center - dotR, width: dotR * 2, height: dotR * 2))

        guard let cgImage = ctx.makeImage() else {
            let fallback = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.8))
                .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
            return (fallback, CGPoint(x: 8, y: 8))
        }

        return (CIImage(cgImage: cgImage), CGPoint(x: center, y: center))
    }

    // MARK: - Click Effects

    private nonisolated static func renderClickEffects(
        in state: CursorOverlayState,
        at timestamp: Double,
        recordingRect: CGRect,
        outputSize: CGSize,
        zoomCropRect: CGRect?
    ) -> CIImage? {
        let settings = state.settings
        let duration = settings.clickEffectDuration
        guard duration > 0 else { return nil }

        let activeClicks = state.clicks.filter { click in
            timestamp >= click.timestamp && timestamp < click.timestamp + duration
        }
        guard !activeClicks.isEmpty else { return nil }

        let outputRect = CGRect(origin: .zero, size: outputSize)
        let canvasW = Int(outputSize.width)
        let canvasH = Int(outputSize.height)

        guard let ctx = CGContext(
            data: nil, width: canvasW, height: canvasH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(origin: .zero, size: outputSize))

        let cec = settings.clickEffectColor
        let color = NSColor(
            red: cec.count > 0 ? cec[0] : 1.0,
            green: cec.count > 1 ? cec[1] : 0.35,
            blue: cec.count > 2 ? cec[2] : 0.37,
            alpha: 1.0
        )

        for click in activeClicks {
            let progress = (timestamp - click.timestamp) / duration
            let eased = progress * progress * (3.0 - 2.0 * progress)  // smoothstep

            let radius = settings.clickEffectMaxRadius * eased
            let opacity = 0.6 * (1.0 - eased)
            let ringWidth = max(1.5, 3.0 * (1.0 - eased))

            let outputPos = mapToOutput(
                cursorX: click.x, cursorY: click.y,
                sourceSize: state.sourceSize,
                recordingRect: recordingRect,
                zoomCropRect: zoomCropRect
            )

            // CGContext uses bottom-left origin
            let cgY = outputSize.height - outputPos.y

            ctx.setStrokeColor(color.withAlphaComponent(opacity).cgColor)
            ctx.setLineWidth(ringWidth)
            ctx.strokeEllipse(in: CGRect(
                x: outputPos.x - radius, y: cgY - radius,
                width: radius * 2, height: radius * 2
            ))
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage).cropped(to: outputRect)
    }

    // MARK: - Zoom Region Generation (first-class editable objects)

    /// Generate zoom regions from click/key clusters — these are user-editable objects persisted in the project.
    nonisolated static func generateZoomRegions(
        clicks: [CursorClick],
        keyInteractions: [(timestamp: Double, x: Double, y: Double)],
        sensitivity: AutoZoomSensitivity,
        zoomLevel: CGFloat,
        sourceSize: CGSize
    ) -> [ZoomRegion] {
        var interactions: [InteractionPoint] = clicks.map {
            InteractionPoint(timestamp: $0.timestamp, x: $0.x, y: $0.y)
        }
        interactions.append(contentsOf: keyInteractions.map {
            InteractionPoint(timestamp: $0.timestamp, x: $0.x, y: $0.y)
        })
        interactions.sort { $0.timestamp < $1.timestamp }

        zoomLog.info("generateZoomRegions: \(interactions.count) interactions, sourceSize=\(Int(sourceSize.width))x\(Int(sourceSize.height)), zoom=\(String(format: "%.1f", zoomLevel))")
        for (i, pt) in interactions.prefix(10).enumerated() {
            zoomLog.info("  interaction[\(i)] t=\(String(format: "%.2f", pt.timestamp)) x=\(String(format: "%.0f", pt.x)) y=\(String(format: "%.0f", pt.y))")
        }

        guard !interactions.isEmpty else { return [] }

        // Cluster interactions by temporal proximity
        var clusters: [(center: CGPoint, startTime: Double, endTime: Double)] = []
        var currentCluster: [InteractionPoint] = []

        for point in interactions {
            if let last = currentCluster.last, point.timestamp - last.timestamp > sensitivity.clusterWindow {
                if currentCluster.count >= sensitivity.minimumClusterSize {
                    let center = averageInteractionPosition(currentCluster)
                    clusters.append((center, currentCluster.first!.timestamp, currentCluster.last!.timestamp))
                }
                currentCluster = [point]
            } else {
                currentCluster.append(point)
            }
        }
        if currentCluster.count >= sensitivity.minimumClusterSize {
            let center = averageInteractionPosition(currentCluster)
            clusters.append((center, currentCluster.first!.timestamp, currentCluster.last!.timestamp))
        }

        for (i, c) in clusters.enumerated() {
            zoomLog.info("  cluster[\(i)] center=(\(String(format: "%.0f", c.center.x)),\(String(format: "%.0f", c.center.y))) t=\(String(format: "%.2f", c.startTime))-\(String(format: "%.2f", c.endTime))")
        }

        guard !clusters.isEmpty else { return [] }

        // Merge overlapping: if clusters are within 1s, merge them
        var merged: [(center: CGPoint, startTime: Double, endTime: Double)] = []
        for cluster in clusters {
            let leadTime = 0.3
            let regionStart = max(0, cluster.startTime - leadTime)
            let regionEnd = cluster.endTime + sensitivity.holdDuration

            if let last = merged.last, regionStart - last.endTime < 1.0 {
                // Merge: average the centers, extend time range
                let avgX = (last.center.x + cluster.center.x) / 2
                let avgY = (last.center.y + cluster.center.y) / 2
                merged[merged.count - 1] = (
                    center: CGPoint(x: avgX, y: avgY),
                    startTime: last.startTime,
                    endTime: regionEnd
                )
            } else {
                merged.append((cluster.center, regionStart, regionEnd))
            }
        }

        // Convert to ZoomRegion
        let regions = merged.map { cluster in
            let clamped = clampFocusPoint(cluster.center, zoom: zoomLevel, sourceSize: sourceSize)
            zoomLog.info("  region: focus raw=(\(String(format: "%.0f", cluster.center.x)),\(String(format: "%.0f", cluster.center.y))) clamped=(\(String(format: "%.0f", clamped.x)),\(String(format: "%.0f", clamped.y))) t=\(String(format: "%.2f", cluster.startTime))-\(String(format: "%.2f", cluster.endTime))")
            return ZoomRegion(
                startTime: cluster.startTime,
                endTime: cluster.endTime,
                zoomLevel: zoomLevel,
                focusX: clamped.x,
                focusY: clamped.y
            )
        }
        return regions
    }

    /// Convert stored zoom regions back to keyframes for the render pipeline.
    ///
    /// The interpolation system transitions FROM prev.zoomLevel TO next.zoomLevel,
    /// starting at prev.timestamp over next.easingDuration. So we need explicit
    /// "hold" keyframes just before each transition to anchor the timing:
    ///
    ///   [hold@1.0] → [zoom-in peak] → [hold@peak] → [zoom-out@1.0]
    ///
    /// This ensures the zoom-in easing happens just before the region starts,
    /// and the zoom-out easing happens at the region end — not at the video start.
    nonisolated static func zoomKeyframes(
        from regions: [ZoomRegion],
        sensitivity: AutoZoomSensitivity,
        sourceSize: CGSize
    ) -> [ZoomKeyframe] {
        let enabledRegions = regions.filter(\.isEnabled).sorted { $0.startTime < $1.startTime }
        guard !enabledRegions.isEmpty else { return [] }

        let sourceCenter = CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        var keyframes: [ZoomKeyframe] = []

        // Start at 1.0
        keyframes.append(ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusPoint: sourceCenter, easingDuration: 0))

        for region in enabledRegions {
            let focus = CGPoint(x: region.focusX, y: region.focusY)
            let zoomInDur = sensitivity.zoomInDuration
            let zoomOutDur = sensitivity.zoomOutDuration

            // Hold at 1.0 until just before zoom-in ramp starts
            let holdTime = max(0.01, region.startTime - zoomInDur)
            keyframes.append(ZoomKeyframe(
                timestamp: holdTime,
                zoomLevel: 1.0,
                focusPoint: sourceCenter,
                easingDuration: 0
            ))

            // Zoom in — the ramp FROM the hold point TO here takes zoomInDur
            keyframes.append(ZoomKeyframe(
                timestamp: region.startTime,
                zoomLevel: region.zoomLevel,
                focusPoint: focus,
                easingDuration: zoomInDur
            ))

            // Hold at peak until zoom-out ramp starts
            let peakHoldEnd = max(region.startTime + 0.01, region.endTime - zoomOutDur)
            keyframes.append(ZoomKeyframe(
                timestamp: peakHoldEnd,
                zoomLevel: region.zoomLevel,
                focusPoint: focus,
                easingDuration: 0
            ))

            // Zoom out — the ramp FROM the peak hold TO here takes zoomOutDur
            keyframes.append(ZoomKeyframe(
                timestamp: region.endTime,
                zoomLevel: 1.0,
                focusPoint: sourceCenter,
                easingDuration: zoomOutDur
            ))
        }

        keyframes.sort { $0.timestamp < $1.timestamp }
        return keyframes
    }

    /// Extract raw interactions from metadata for zoom region generation.
    nonisolated static func extractInteractions(
        from metadata: CursorMetadataFile
    ) -> (clicks: [CursorClick], keyInteractions: [(timestamp: Double, x: Double, y: Double)], sourceSize: CGSize) {
        let sourceSize = CGSize(width: metadata.sourceSize.width, height: metadata.sourceSize.height)
        let captureOrigin: CGPoint
        if let origin = metadata.captureOrigin {
            captureOrigin = CGPoint(x: origin.x, y: origin.y)
        } else {
            captureOrigin = .zero
        }

        let clicks: [CursorClick] = metadata.events
            .filter { $0.type == .click }
            .compactMap { event in
                guard let button = event.button else { return nil }
                let videoX = event.x - captureOrigin.x
                let videoY = sourceSize.height - (event.y - captureOrigin.y)
                return CursorClick(timestamp: event.timestamp, x: videoX, y: videoY, button: button)
            }

        let keyInteractions: [(timestamp: Double, x: Double, y: Double)] = metadata.events
            .filter { $0.type == .keyDown }
            .map { event in
                let videoX = event.x - captureOrigin.x
                let videoY = sourceSize.height - (event.y - captureOrigin.y)
                return (event.timestamp, videoX, videoY)
            }

        return (clicks, keyInteractions, sourceSize)
    }

    // MARK: - Auto-Zoom Keyframe Generation (legacy — kept for reference)

    /// Unified interaction point for zoom clustering (clicks + keyboard activity)
    private struct InteractionPoint: Sendable {
        var timestamp: Double
        var x: Double
        var y: Double
    }

    private nonisolated static func generateZoomKeyframes(
        clicks: [CursorClick],
        keyInteractions: [(timestamp: Double, x: Double, y: Double)] = [],
        sensitivity: AutoZoomSensitivity,
        zoomLevel: CGFloat,
        sourceSize: CGSize
    ) -> [ZoomKeyframe] {
        // Merge clicks + key interactions into unified interaction points, sorted by time
        var interactions: [InteractionPoint] = clicks.map {
            InteractionPoint(timestamp: $0.timestamp, x: $0.x, y: $0.y)
        }
        interactions.append(contentsOf: keyInteractions.map {
            InteractionPoint(timestamp: $0.timestamp, x: $0.x, y: $0.y)
        })
        interactions.sort { $0.timestamp < $1.timestamp }

        guard !interactions.isEmpty else { return [] }

        // Cluster interactions by temporal proximity
        var clusters: [(center: CGPoint, startTime: Double, endTime: Double)] = []
        var currentCluster: [InteractionPoint] = []

        for point in interactions {
            if let last = currentCluster.last, point.timestamp - last.timestamp > sensitivity.clusterWindow {
                if currentCluster.count >= sensitivity.minimumClusterSize {
                    let center = averageInteractionPosition(currentCluster)
                    clusters.append((center, currentCluster.first!.timestamp, currentCluster.last!.timestamp))
                }
                currentCluster = [point]
            } else {
                currentCluster.append(point)
            }
        }
        if currentCluster.count >= sensitivity.minimumClusterSize {
            let center = averageInteractionPosition(currentCluster)
            clusters.append((center, currentCluster.first!.timestamp, currentCluster.last!.timestamp))
        }

        guard !clusters.isEmpty else { return [] }

        // Generate keyframes
        var keyframes: [ZoomKeyframe] = []
        let sourceCenter = CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)

        for cluster in clusters {
            let leadTime = 0.3
            let clampedFocus = clampFocusPoint(cluster.center, zoom: zoomLevel, sourceSize: sourceSize)

            // Zoom in
            keyframes.append(ZoomKeyframe(
                timestamp: max(0, cluster.startTime - leadTime),
                zoomLevel: zoomLevel,
                focusPoint: clampedFocus,
                easingDuration: sensitivity.zoomInDuration
            ))

            // Zoom out
            keyframes.append(ZoomKeyframe(
                timestamp: cluster.endTime + sensitivity.holdDuration,
                zoomLevel: 1.0,
                focusPoint: sourceCenter,
                easingDuration: sensitivity.zoomOutDuration
            ))
        }

        // Merge overlapping: if a zoom-out is followed by a zoom-in within 1s, remove both
        keyframes.sort { $0.timestamp < $1.timestamp }
        var merged: [ZoomKeyframe] = []
        for kf in keyframes {
            if let last = merged.last, kf.zoomLevel > 1.001, last.zoomLevel < 1.001,
               kf.timestamp - last.timestamp < 1.0 {
                merged.removeLast()  // remove the zoom-out
            }
            merged.append(kf)
        }

        // Ensure we start at 1.0
        if merged.first?.timestamp ?? 0 > 0.1 {
            merged.insert(ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusPoint: sourceCenter, easingDuration: 0), at: 0)
        }

        return merged
    }

    private nonisolated static func averagePosition(_ clicks: [CursorClick]) -> CGPoint {
        let sumX = clicks.reduce(0.0) { $0 + $1.x }
        let sumY = clicks.reduce(0.0) { $0 + $1.y }
        let count = Double(clicks.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private nonisolated static func averageInteractionPosition(_ points: [InteractionPoint]) -> CGPoint {
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let count = Double(points.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private nonisolated static func clampFocusPoint(_ point: CGPoint, zoom: CGFloat, sourceSize: CGSize) -> CGPoint {
        let halfW = (sourceSize.width / zoom) / 2
        let halfH = (sourceSize.height / zoom) / 2
        let x = max(halfW, min(sourceSize.width - halfW, point.x))
        let y = max(halfH, min(sourceSize.height - halfH, point.y))
        return CGPoint(x: x, y: y)
    }

    // MARK: - Zoom Interpolation

    private nonisolated static func interpolateZoom(
        keyframes: [ZoomKeyframe],
        at timestamp: Double
    ) -> (zoom: CGFloat, focus: CGPoint) {
        guard !keyframes.isEmpty else { return (1.0, .zero) }
        if timestamp <= keyframes.first!.timestamp {
            return (keyframes.first!.zoomLevel, keyframes.first!.focusPoint)
        }
        if timestamp >= keyframes.last!.timestamp {
            return (keyframes.last!.zoomLevel, keyframes.last!.focusPoint)
        }

        // Find bracketing keyframes
        var prevIdx = 0
        for i in 0..<keyframes.count {
            if keyframes[i].timestamp <= timestamp { prevIdx = i }
            else { break }
        }
        let nextIdx = min(prevIdx + 1, keyframes.count - 1)

        let prev = keyframes[prevIdx]
        let next = keyframes[nextIdx]
        let range = next.easingDuration
        guard range > 0.001 else { return (next.zoomLevel, next.focusPoint) }

        let elapsed = timestamp - prev.timestamp
        let t = min(1.0, max(0.0, elapsed / range))
        let eased = t * t * (3.0 - 2.0 * t)  // smoothstep

        let zoom = prev.zoomLevel + (next.zoomLevel - prev.zoomLevel) * eased
        let fx = prev.focusPoint.x + (next.focusPoint.x - prev.focusPoint.x) * eased
        let fy = prev.focusPoint.y + (next.focusPoint.y - prev.focusPoint.y) * eased

        return (zoom, CGPoint(x: fx, y: fy))
    }

    // MARK: - Reverse remap (source time → composition time)

    private nonisolated static func compositionTime(
        forSourceTime sourceT: Double,
        in table: TimeRemapTable
    ) -> Double? {
        guard !table.entries.isEmpty else { return sourceT }

        // Find closest entries by source time
        var bestIdx = 0
        var bestDist = Double.infinity
        for (i, entry) in table.entries.enumerated() {
            let dist = abs(entry.sourceTime - sourceT)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }

        // If exact enough, return the composition time
        guard bestDist < 1.0 else { return nil }  // click outside enabled segments
        return table.entries[bestIdx].compositionTime
    }
}

