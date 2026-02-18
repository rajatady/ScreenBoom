import Testing
import SwiftUI
import AppKit
@testable import Screenboom

@MainActor
struct EditorSettingsBindingsTests {
    private func makeProject() -> Project {
        let project = Project()
        project.segments = [Segment(startTime: 0, endTime: 10, speed: 1.0, isEnabled: true)]
        project.videoSize = CGSize(width: 1920, height: 1080)
        return project
    }

    @Test func backgroundTypeSelectionTransitionsAcrossAllModes() {
        let project = makeProject()
        let controller = EditorSettingsController(project: project)

        controller.setBackgroundTypeSelection(.solid)
        if case .solid = project.backgroundStyle {
            #expect(true)
        } else {
            Issue.record("Expected solid background style")
        }

        controller.setBackgroundTypeSelection(.gradient)
        if case .gradient = project.backgroundStyle {
            #expect(true)
        } else {
            Issue.record("Expected gradient background style")
        }

        controller.setBackgroundTypeSelection(.mesh)
        if case .mesh = project.backgroundStyle {
            #expect(true)
        } else {
            Issue.record("Expected mesh background style")
        }

        controller.setBackgroundTypeSelection(.wallpaper)
        if case .wallpaper(let name) = project.backgroundStyle {
            #expect(name == "Sunset")
        } else {
            Issue.record("Expected wallpaper background style")
        }
    }

    @Test func frameStyleSelectionTransitionsAcrossAllModes() {
        let project = makeProject()
        let controller = EditorSettingsController(project: project)

        controller.setFrameStyleSelection(.none)
        #expect(controller.frameStyleSelection == .none)

        controller.setFrameStyleSelection(.border)
        #expect(controller.frameStyleSelection == .border)

        controller.setFrameStyleSelection(.glow)
        #expect(controller.frameStyleSelection == .glow)

        controller.setFrameStyleSelection(.browser)
        #expect(controller.frameStyleSelection == .browser)

        controller.setFrameStyleSelection(.window)
        #expect(controller.frameStyleSelection == .window)
    }

    @Test func gradientAndSolidBindingsWriteThroughToProject() {
        let project = makeProject()
        let controller = EditorSettingsController(project: project)

        let gradient1 = controller.gradientColor1Binding()
        gradient1.wrappedValue = Color(red: 0.3, green: 0.4, blue: 0.5)
        let c1 = NSColor(project.gradientColor1).usingColorSpace(.sRGB)!
        #expect(abs(c1.redComponent - 0.3) < 0.03)

        let gradient2 = controller.gradientColor2Binding()
        gradient2.wrappedValue = Color(red: 0.1, green: 0.2, blue: 0.9)
        let c2 = NSColor(project.gradientColor2).usingColorSpace(.sRGB)!
        #expect(abs(c2.blueComponent - 0.9) < 0.03)

        let solid = controller.solidColorBinding()
        solid.wrappedValue = Color(red: 0.7, green: 0.2, blue: 0.1)
        if case .solid(let color) = project.backgroundStyle {
            #expect(abs(color.red - 0.7) < 0.03)
            #expect(abs(color.green - 0.2) < 0.03)
            #expect(abs(color.blue - 0.1) < 0.03)
        } else {
            Issue.record("Expected solid background after solidColorBinding set")
        }
    }

    @Test func meshAndFrameBindingsUpdateUnderlyingStyles() {
        let project = makeProject()
        let controller = EditorSettingsController(project: project)

        controller.setBackgroundTypeSelection(.mesh)
        let topLeftBinding = controller.meshColorBinding(corner: .topLeft)
        topLeftBinding.wrappedValue = Color(red: 0.9, green: 0.1, blue: 0.2)
        if case .mesh(let tl, _, _, _) = project.backgroundStyle {
            #expect(abs(tl.red - 0.9) < 0.03)
            #expect(abs(tl.green - 0.1) < 0.03)
            #expect(abs(tl.blue - 0.2) < 0.03)
        } else {
            Issue.record("Expected mesh background")
        }

        project.frameStyle = .border(width: 2, color: CodableColor(red: 1, green: 1, blue: 1))
        let borderWidth = controller.borderWidthBinding()
        borderWidth.wrappedValue = 6
        if case .border(let width, _) = project.frameStyle {
            #expect(abs(width - 6) < 0.0001)
        } else {
            Issue.record("Expected border frame style")
        }

        let borderColor = controller.borderColorBinding()
        borderColor.wrappedValue = Color(red: 0.4, green: 0.5, blue: 0.6)
        if case .border(_, let color) = project.frameStyle {
            #expect(abs(color.red - 0.4) < 0.03)
            #expect(abs(color.green - 0.5) < 0.03)
            #expect(abs(color.blue - 0.6) < 0.03)
        } else {
            Issue.record("Expected border frame style")
        }

        project.frameStyle = .neonGlow(color: CodableColor(red: 1, green: 0, blue: 0), radius: 10)
        let glowColor = controller.glowColorBinding()
        glowColor.wrappedValue = Color(red: 0.2, green: 0.9, blue: 0.3)
        let glowRadius = controller.glowRadiusBinding()
        glowRadius.wrappedValue = 24
        if case .neonGlow(let color, let radius) = project.frameStyle {
            #expect(abs(color.red - 0.2) < 0.03)
            #expect(abs(color.green - 0.9) < 0.03)
            #expect(abs(color.blue - 0.3) < 0.03)
            #expect(abs(radius - 24) < 0.0001)
        } else {
            Issue.record("Expected glow frame style")
        }
    }

    @Test func layoutAndAutoZoomBindingsUpdateProjectState() {
        let project = makeProject()
        let controller = EditorSettingsController(project: project)

        let padding = controller.paddingBinding()
        let cornerRadius = controller.cornerRadiusBinding()
        let shadowRadius = controller.shadowRadiusBinding()
        let shadowOpacity = controller.shadowOpacityBinding()
        let autoZoom = controller.autoZoomLevelBinding()

        padding.wrappedValue = 80
        cornerRadius.wrappedValue = 22
        shadowRadius.wrappedValue = 44
        shadowOpacity.wrappedValue = 0.65
        autoZoom.wrappedValue = 2.4

        #expect(abs(project.padding - 80) < 0.0001)
        #expect(abs(project.cornerRadius - 22) < 0.0001)
        #expect(abs(project.shadowRadius - 44) < 0.0001)
        #expect(abs(project.shadowOpacity - 0.65) < 0.0001)
        #expect(abs(project.cursorSettings.autoZoomLevel - 2.4) < 0.0001)
    }
}
