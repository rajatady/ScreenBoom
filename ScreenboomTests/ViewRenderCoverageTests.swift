import Testing
import SwiftUI
import AppKit
import AVFoundation
@testable import Screenboom

@MainActor
struct ViewRenderCoverageTests {
    private func host<V: View>(_ root: V, size: CGSize = CGSize(width: 900, height: 700)) -> NSHostingView<AnyView> {
        let wrapped = AnyView(
            root.frame(width: size.width, height: size.height)
        )
        let hosting = NSHostingView(rootView: wrapped)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        _ = hosting.fittingSize
        return hosting
    }

    private func mountInHiddenWindow(_ view: NSView, size: CGSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func disposeWindow(_ window: NSWindow) {
        window.contentView = nil
        window.orderOut(nil)
    }

    private func assertHostedSize(_ hosting: NSHostingView<AnyView>) {
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width >= 0)
        #expect(hosting.fittingSize.height >= 0)
    }

    private func hostInHiddenWindow<V: View>(_ root: V, size: CGSize = CGSize(width: 900, height: 700)) -> NSWindow {
        let hosting = NSHostingView(rootView: root)
        return mountInHiddenWindow(hosting, size: size)
    }

    private func makeProject(withCursorData: Bool = false) throws -> Project {
        let project = Project()
        project.duration = CMTime(seconds: 12, preferredTimescale: 600)
        project.videoSize = CGSize(width: 1920, height: 1080)
        project.segments = [
            Segment(startTime: 0, endTime: 6, speed: 1.0, isEnabled: true),
            Segment(startTime: 6, endTime: 12, speed: 1.5, isEnabled: true),
        ]
        if withCursorData {
            let metadata = CursorMetadataFile(
                frameRate: 60,
                sourceSize: .init(width: 1920, height: 1080),
                captureOrigin: .init(x: 0, y: 0),
                displayHeight: 1080,
                backingScaleFactor: 1.0,
                events: [
                    CursorEvent(timestamp: 0.5, x: 300, y: 700, type: .move, button: nil),
                    CursorEvent(timestamp: 1.0, x: 400, y: 650, type: .click, button: .left),
                ]
            )
            let metadataURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("view-render-cursor-\(UUID().uuidString).json")
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            project.cursorMetadataURL = metadataURL
            project.loadCursorMetadata()
        }
        return project
    }

    @Test func controlsAndTabsRenderWithCursorData() throws {
        let project = try makeProject(withCursorData: true)
        let controller = EditorSettingsController(project: project)
        #expect(controller.availableTabs.contains(.appearance))
        #expect(controller.availableTabs.contains(.cursor))
        #expect(controller.availableTabs.contains(.zoom))

        var hosting = host(ControlsPanel(controller: controller))
        assertHostedSize(hosting)

        hosting = host(AppearanceTabView(controller: controller))
        assertHostedSize(hosting)

        hosting = host(CursorTabView(controller: controller))
        assertHostedSize(hosting)

        controller.setAutoZoomEnabled(true)
        hosting = host(ZoomTabView(controller: controller))
        assertHostedSize(hosting)
    }

    @Test func contextualInspectorRendersSegmentAndZoomModes() throws {
        let project = try makeProject(withCursorData: true)
        let controller = EditorSettingsController(project: project)

        project.selectedSegmentId = project.segments[0].id
        var hosting = host(ContextualInspectorView(controller: controller))
        assertHostedSize(hosting)

        project.selectedSegmentId = nil
        let region = ZoomRegion(startTime: 1.0, endTime: 3.0, zoomLevel: 1.7, focusX: 700, focusY: 420)
        project.zoomRegions = [region]
        project.selectedZoomRegionID = region.id
        hosting = host(ContextualInspectorView(controller: controller))
        assertHostedSize(hosting)
    }

    @Test func countdownPanelAndOverlayRender() {
        let panel = CountdownFloatingPanel()
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        panel.orderOut(nil)

        let model = CountdownModel()
        model.count = 2
        let hosting = host(CountdownOverlayView(model: model), size: CGSize(width: 300, height: 300))
        assertHostedSize(hosting)
    }

    @Test func recorderBarRendersConfigCountdownRecordingAndFailureStates() {
        let flow = RecorderFlowController()
        flow.captureMode = .region
        flow._setSelectedRegionForTesting(CGRect(x: 10, y: 20, width: 640, height: 360))
        flow._setFlowStateForTesting(.configuring)

        var hosting = host(
            RecorderBarView(
                flow: flow,
                onComplete: { _ in },
                onDismiss: {}
            ),
            size: CGSize(width: 800, height: 200)
        )
        assertHostedSize(hosting)

        flow._setFlowStateForTesting(.countdown(2))
        hosting = host(
            RecorderBarView(
                flow: flow,
                onComplete: { _ in },
                onDismiss: {}
            ),
            size: CGSize(width: 800, height: 200)
        )
        assertHostedSize(hosting)

        flow._setFlowStateForTesting(.recording)
        hosting = host(
            RecorderBarView(
                flow: flow,
                onComplete: { _ in },
                onDismiss: {}
            ),
            size: CGSize(width: 800, height: 200)
        )
        assertHostedSize(hosting)

        flow._setFlowStateForTesting(.failed("Permission denied"))
        hosting = host(
            RecorderBarView(
                flow: flow,
                onComplete: { _ in },
                onDismiss: {}
            ),
            size: CGSize(width: 900, height: 220)
        )
        assertHostedSize(hosting)
    }

    @Test func recorderBarCompletedStateInvokesCompletionCallback() async {
        let flow = RecorderFlowController()
        let session = RecordingSession(
            videoURL: URL(fileURLWithPath: "/tmp/render.mp4"),
            cursorMetadataURL: nil,
            duration: 2.0,
            sourceSize: CGSize(width: 1920, height: 1080),
            frameRate: 60,
            displayName: "Render",
            startDate: Date(timeIntervalSince1970: 0)
        )
        flow._setFlowStateForTesting(.completed(session))

        var completedName: String?
        let window = hostInHiddenWindow(
            RecorderBarView(
                flow: flow,
                onComplete: { completed in completedName = completed.displayName },
                onDismiss: {}
            ),
            size: CGSize(width: 400, height: 120)
        )
        defer { disposeWindow(window) }

        try? await Task.sleep(for: .milliseconds(20))
        #expect(completedName == "Render")
    }
}
