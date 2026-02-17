import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - Background Type Picker

enum BackgroundTypeSelection: String, CaseIterable {
    case solid = "Solid"
    case gradient = "Gradient"
    case mesh = "Mesh"
    case wallpaper = "Wallpaper"
    case image = "Image"
}

// MARK: - Frame Style Selection

enum FrameStyleSelection: String, CaseIterable {
    case none = "None"
    case border = "Border"
    case glow = "Glow"
    case browser = "Browser"
    case window = "Window"
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

    var backgroundStyle: BackgroundType { project.backgroundStyle }
    var frameStyle: FrameStyle { project.frameStyle }

    // MARK: - Background Type Selection

    var backgroundTypeSelection: BackgroundTypeSelection {
        switch project.backgroundStyle {
        case .solid: .solid
        case .gradient: .gradient
        case .mesh: .mesh
        case .wallpaper: .wallpaper
        case .image: .image
        }
    }

    var frameStyleSelection: FrameStyleSelection {
        switch project.frameStyle {
        case .none: .none
        case .border, .gradientBorder: .border
        case .neonGlow: .glow
        case .browserChrome: .browser
        case .macOSWindow: .window
        }
    }

    // MARK: - Background Presets (legacy gradient presets)

    static let backgroundPresets: [(name: String, color1: Color, color2: Color)] = [
        ("Dark", Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.18, green: 0.12, blue: 0.28)),
        ("Light", Color(red: 0.92, green: 0.92, blue: 0.96), Color(red: 0.85, green: 0.88, blue: 0.95)),
        ("Ocean", Color(red: 0.05, green: 0.1, blue: 0.3), Color(red: 0.1, green: 0.2, blue: 0.5)),
    ]

    var currentPreset: String? {
        guard case .gradient(let gc1, let gc2) = project.backgroundStyle else { return nil }
        for preset in Self.backgroundPresets {
            let pc1 = NSColor(preset.color1).usingColorSpace(.sRGB)
            let pc2 = NSColor(preset.color2).usingColorSpace(.sRGB)
            if let pc1, let pc2,
               abs(gc1.red - pc1.redComponent) < 0.02,
               abs(gc1.green - pc1.greenComponent) < 0.02,
               abs(gc1.blue - pc1.blueComponent) < 0.02,
               abs(gc2.red - pc2.redComponent) < 0.02,
               abs(gc2.green - pc2.greenComponent) < 0.02,
               abs(gc2.blue - pc2.blueComponent) < 0.02 {
                return preset.name
            }
        }
        return nil
    }

    // MARK: - Actions

    func applyPreset(_ name: String) {
        guard let preset = Self.backgroundPresets.first(where: { $0.name == name }) else { return }
        project.backgroundStyle = .gradient(CodableColor(swiftUI: preset.color1), CodableColor(swiftUI: preset.color2))
        project.updateVisuals()
    }

    func setBackgroundType(_ style: BackgroundType) {
        project.backgroundStyle = style
        project.updateVisuals()
    }

    func setBackgroundTypeSelection(_ selection: BackgroundTypeSelection) {
        switch selection {
        case .solid:
            // Convert current to solid using first gradient color or default
            if case .gradient(let c1, _) = project.backgroundStyle {
                project.backgroundStyle = .solid(c1)
            } else {
                project.backgroundStyle = .solid(CodableColor(red: 0.1, green: 0.1, blue: 0.12))
            }
        case .gradient:
            if case .gradient = project.backgroundStyle { return }
            project.backgroundStyle = .defaultStyle
        case .mesh:
            if case .mesh = project.backgroundStyle { return }
            project.backgroundStyle = .mesh(
                topLeft: CodableColor(red: 0.08, green: 0.08, blue: 0.20),
                topRight: CodableColor(red: 0.20, green: 0.08, blue: 0.30),
                bottomLeft: CodableColor(red: 0.05, green: 0.15, blue: 0.15),
                bottomRight: CodableColor(red: 0.15, green: 0.10, blue: 0.25)
            )
        case .wallpaper:
            if case .wallpaper = project.backgroundStyle { return }
            project.backgroundStyle = .wallpaper("Sunset")
        case .image:
            if case .image = project.backgroundStyle { return }
            importBackgroundImage()
            return
        }
        project.updateVisuals()
    }

    func setFrameStyle(_ style: FrameStyle) {
        project.frameStyle = style
        project.updateVisuals()
    }

    func setFrameStyleSelection(_ selection: FrameStyleSelection) {
        switch selection {
        case .none:
            project.frameStyle = .none
        case .border:
            if case .border = project.frameStyle { return }
            project.frameStyle = .border(width: 2, color: CodableColor(red: 1, green: 1, blue: 1, alpha: 0.2))
        case .glow:
            if case .neonGlow = project.frameStyle { return }
            project.frameStyle = .neonGlow(color: CodableColor(red: 1.0, green: 0.35, blue: 0.37), radius: 12)
        case .browser:
            project.frameStyle = .browserChrome
        case .window:
            project.frameStyle = .macOSWindow
        }
        project.updateVisuals()
    }

    func selectWallpaper(_ name: String) {
        project.backgroundStyle = .wallpaper(name)
        project.updateVisuals()
    }

    func importBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            // Create bookmark data for persistence
            if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                self.project.backgroundStyle = .image(bookmarkData)
                self.project.updateVisuals()
            } else if let bookmarkData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                self.project.backgroundStyle = .image(bookmarkData)
                self.project.updateVisuals()
            }
        }
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

    func solidColorBinding() -> Binding<Color> {
        Binding(
            get: { [weak project] in
                guard let project else { return .black }
                if case .solid(let c) = project.backgroundStyle { return c.toColor() }
                return .black
            },
            set: { [weak project] in
                project?.backgroundStyle = .solid(CodableColor(swiftUI: $0))
                project?.updateVisuals()
            }
        )
    }

    func meshColorBinding(corner: MeshCorner) -> Binding<Color> {
        Binding(
            get: { [weak project] in
                guard let project, case .mesh(let tl, let tr, let bl, let br) = project.backgroundStyle else { return .black }
                switch corner {
                case .topLeft: return tl.toColor()
                case .topRight: return tr.toColor()
                case .bottomLeft: return bl.toColor()
                case .bottomRight: return br.toColor()
                }
            },
            set: { [weak project] newColor in
                guard let project, case .mesh(var tl, var tr, var bl, var br) = project.backgroundStyle else { return }
                let cc = CodableColor(swiftUI: newColor)
                switch corner {
                case .topLeft: tl = cc
                case .topRight: tr = cc
                case .bottomLeft: bl = cc
                case .bottomRight: br = cc
                }
                project.backgroundStyle = .mesh(topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br)
                project.updateVisuals()
            }
        )
    }

    func borderWidthBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in
                guard let project else { return 2 }
                if case .border(let w, _) = project.frameStyle { return w }
                return 2
            },
            set: { [weak project] in
                guard let project else { return }
                if case .border(_, let c) = project.frameStyle {
                    project.frameStyle = .border(width: $0, color: c)
                    project.updateVisuals()
                }
            }
        )
    }

    func borderColorBinding() -> Binding<Color> {
        Binding(
            get: { [weak project] in
                guard let project else { return .white }
                if case .border(_, let c) = project.frameStyle { return c.toColor() }
                return .white
            },
            set: { [weak project] in
                guard let project else { return }
                if case .border(let w, _) = project.frameStyle {
                    project.frameStyle = .border(width: w, color: CodableColor(swiftUI: $0))
                    project.updateVisuals()
                }
            }
        )
    }

    func glowColorBinding() -> Binding<Color> {
        Binding(
            get: { [weak project] in
                guard let project else { return SB.Colors.accent }
                if case .neonGlow(let c, _) = project.frameStyle { return c.toColor() }
                return SB.Colors.accent
            },
            set: { [weak project] in
                guard let project else { return }
                if case .neonGlow(_, let r) = project.frameStyle {
                    project.frameStyle = .neonGlow(color: CodableColor(swiftUI: $0), radius: r)
                    project.updateVisuals()
                }
            }
        )
    }

    func glowRadiusBinding() -> Binding<CGFloat> {
        Binding(
            get: { [weak project] in
                guard let project else { return 12 }
                if case .neonGlow(_, let r) = project.frameStyle { return r }
                return 12
            },
            set: { [weak project] in
                guard let project else { return }
                if case .neonGlow(let c, _) = project.frameStyle {
                    project.frameStyle = .neonGlow(color: c, radius: $0)
                    project.updateVisuals()
                }
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

// MARK: - Mesh Corner

enum MeshCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}
