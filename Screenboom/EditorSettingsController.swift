import SwiftUI

// MARK: - Editor Tab

enum EditorTab: String, CaseIterable, Identifiable {
    case appearance
    case cursor
    case zoom
    case audio
    case annotations
    case subtitles

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: "paintbrush.pointed"
        case .cursor: "cursorarrow.motionlines"
        case .zoom: "plus.magnifyingglass"
        case .audio: "waveform"
        case .annotations: "pencil.tip.crop.circle"
        case .subtitles: "captions.bubble"
        }
    }

    var label: String {
        switch self {
        case .appearance: "Appearance"
        case .cursor: "Cursor"
        case .zoom: "Zoom"
        case .audio: "Audio"
        case .annotations: "Annotations"
        case .subtitles: "Subtitles"
        }
    }

    var isComingSoon: Bool {
        switch self {
        case .audio, .annotations, .subtitles: true
        default: false
        }
    }
}

// MARK: - EditorSettingsController

@Observable
final class EditorSettingsController {
    let project: Project
    var selectedTab: EditorTab = .appearance

    init(project: Project) {
        self.project = project
    }

    // MARK: - Tab Availability

    var availableTabs: [EditorTab] {
        EditorTab.allCases.filter { tab in
            switch tab {
            case .cursor, .zoom:
                return project.hasCursorData
            default:
                return true
            }
        }
    }

    func isTabAvailable(_ tab: EditorTab) -> Bool {
        availableTabs.contains(tab)
    }

    // MARK: - Read-through Properties

    var hasCursorData: Bool { project.hasCursorData }

    var selectedZoomRegion: ZoomRegion? {
        guard let id = project.selectedZoomRegionID else { return nil }
        return project.zoomRegions.first { $0.id == id }
    }

    var selectedSegment: Segment? {
        guard let id = project.selectedSegmentId else { return nil }
        return project.segments.first { $0.id == id }
    }

    var hasInspectorContent: Bool {
        selectedZoomRegion != nil || selectedSegment != nil
    }

    // MARK: - Background Presets

    static let backgroundPresets: [(name: String, color1: Color, color2: Color)] = [
        ("Dark", Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.18, green: 0.12, blue: 0.28)),
        ("Light", Color(red: 0.92, green: 0.92, blue: 0.96), Color(red: 0.85, green: 0.88, blue: 0.95)),
        ("Ocean", Color(red: 0.05, green: 0.1, blue: 0.3), Color(red: 0.1, green: 0.2, blue: 0.5)),
    ]

    var currentPreset: String? {
        for preset in Self.backgroundPresets {
            let nc1 = NSColor(project.gradientColor1).usingColorSpace(.sRGB)
            let nc2 = NSColor(project.gradientColor2).usingColorSpace(.sRGB)
            let pc1 = NSColor(preset.color1).usingColorSpace(.sRGB)
            let pc2 = NSColor(preset.color2).usingColorSpace(.sRGB)
            if let nc1, let nc2, let pc1, let pc2,
               abs(nc1.redComponent - pc1.redComponent) < 0.02,
               abs(nc1.greenComponent - pc1.greenComponent) < 0.02,
               abs(nc1.blueComponent - pc1.blueComponent) < 0.02,
               abs(nc2.redComponent - pc2.redComponent) < 0.02,
               abs(nc2.greenComponent - pc2.greenComponent) < 0.02,
               abs(nc2.blueComponent - pc2.blueComponent) < 0.02 {
                return preset.name
            }
        }
        return nil
    }

    // MARK: - Actions

    func applyPreset(_ name: String) {
        guard let preset = Self.backgroundPresets.first(where: { $0.name == name }) else { return }
        project.gradientColor1 = preset.color1
        project.gradientColor2 = preset.color2
        project.updateVisuals()
    }

    func setCursorEnabled(_ enabled: Bool) {
        project.cursorSettings.isEnabled = enabled
        project.rebuildCursorOverlay()
        project.updateVisuals()
    }

    func setCursorStyle(_ style: CursorStyle) {
        project.cursorSettings.style = style
        project.rebuildCursorOverlay()
        project.updateVisuals()
    }

    func setCursorSize(_ size: CGFloat) {
        project.cursorSettings.size = size
        project.rebuildCursorOverlay()
        project.updateVisuals()
    }

    func setClickEffectEnabled(_ enabled: Bool) {
        project.cursorSettings.clickEffectEnabled = enabled
        project.rebuildCursorOverlay()
        project.updateVisuals()
    }

    func setClickEffectRadius(_ radius: CGFloat) {
        project.cursorSettings.clickEffectMaxRadius = radius
        project.rebuildCursorOverlay()
        project.updateVisuals()
    }

    func setAutoZoomEnabled(_ enabled: Bool) {
        project.cursorSettings.autoZoomEnabled = enabled
        if enabled && project.zoomRegions.isEmpty {
            project.generateAutoZoomRegions()
        } else {
            project.rebuildCursorOverlay()
            project.updateVisuals()
        }
    }

    func setAutoZoomSensitivity(_ sensitivity: AutoZoomSensitivity) {
        project.cursorSettings.autoZoomSensitivity = sensitivity
        project.rebuildCursorOverlay()
        project.updateVisuals()
    }

    func regenerateZoomRegions() {
        project.generateAutoZoomRegions()
    }

    func dismissInspector() {
        project.selectedZoomRegionID = nil
        project.selectedSegmentId = nil
    }

    func toggleSegment(_ id: UUID) {
        project.toggleSegment(id)
    }

    func setSegmentSpeed(_ speed: Double, for id: UUID) {
        project.setSpeed(speed, for: id)
    }

    func setOutputResolution(width: Double, height: Double) {
        project.outputWidth = width
        project.outputHeight = height
        project.saveState()
    }

    // MARK: - Binding Factories

    func gradientColor1Binding() -> Binding<Color> {
        Binding(
            get: { [weak project] in project?.gradientColor1 ?? .black },
            set: { [weak project] in
                project?.gradientColor1 = $0
                project?.updateVisuals()
            }
        )
    }

    func gradientColor2Binding() -> Binding<Color> {
        Binding(
            get: { [weak project] in project?.gradientColor2 ?? .black },
            set: { [weak project] in
                project?.gradientColor2 = $0
                project?.updateVisuals()
            }
        )
    }

    func paddingBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in project?.padding ?? 60 },
            set: { [weak project] in
                project?.padding = $0
                project?.updateVisuals()
            }
        )
    }

    func cornerRadiusBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in project?.cornerRadius ?? 16 },
            set: { [weak project] in
                project?.cornerRadius = $0
                project?.updateVisuals()
            }
        )
    }

    func shadowRadiusBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in project?.shadowRadius ?? 30 },
            set: { [weak project] in
                project?.shadowRadius = $0
                project?.updateVisuals()
            }
        )
    }

    func shadowOpacityBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in project?.shadowOpacity ?? 0.5 },
            set: { [weak project] in
                project?.shadowOpacity = $0
                project?.updateVisuals()
            }
        )
    }

    func autoZoomLevelBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in project?.cursorSettings.autoZoomLevel ?? 1.3 },
            set: { [weak project] in project?.cursorSettings.autoZoomLevel = $0 }
        )
    }
}
