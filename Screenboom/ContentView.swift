import SwiftUI

struct ContentView: View {
    @Bindable var project: Project
    var store: ProjectStore
    @Namespace private var heroAnimation
    @Environment(ExportPanelManager.self) private var exportPanelManager
    @State private var editorSettings: EditorSettingsController?

    private var showEditor: Bool {
        project.currentProjectID != nil
    }

    var body: some View {
        ZStack {
            if showEditor {
                editorView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)).animation(SB.Anim.springGentle),
                        removal: .opacity.combined(with: .scale(scale: 1.02)).animation(SB.Anim.springGentle)
                    ))
            } else {
                WelcomeView(project: project, store: store, heroNamespace: heroAnimation)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)).animation(SB.Anim.springGentle),
                        removal: .opacity.combined(with: .scale(scale: 0.97)).animation(SB.Anim.springGentle)
                    ))
            }
        }
        .animation(SB.Anim.springGentle, value: showEditor)
        .onChange(of: showEditor) { _, isEditor in
            if isEditor {
                editorSettings = EditorSettingsController(project: project)
            } else {
                editorSettings = nil
            }
        }
    }

    private var editorView: some View {
        HSplitView {
            VStack(spacing: 0) {
                // Toolbar — glass-backed
                HStack {
                    SBSecondaryButton(title: "Back", icon: "chevron.left", compact: true) {
                        project.closeProject()
                    }
                    .disabled(project.isClosingProject)
                    .accessibilityIdentifier("editor_back_button")

                    Spacer()

                    // Export button
                if !project.isLoadingProject {
                    exportButton
                }
            }
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.sm)
                .background(.ultraThinMaterial)

                ZStack {
                    if project.isLoadingProject || project.isClosingProject {
                        // Lightweight placeholder during transition
                        loadingPlaceholder
                    } else {
                        VideoPreviewView(project: project)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .matchedGeometryEffect(id: "hero-\(project.currentProjectID ?? UUID())", in: heroAnimation)

                if !project.isLoadingProject && !project.isClosingProject {
                    Divider()

                    TimelineView(project: project)
                        .frame(height: project.hasCursorData ? SB.Layout.timelineHeightWithZoom : SB.Layout.timelineHeight)
                        .accessibilityIdentifier("editor_timeline")
                }
            }

            if let settings = editorSettings, !project.isLoadingProject, !project.isClosingProject {
                ControlsPanel(controller: settings)
                    .frame(width: SB.Layout.controlPanelWidth)
                    .accessibilityIdentifier("editor_controls_panel")
            }
        }
        .accessibilityIdentifier("editor_root")
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: SB.Space.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(SB.Colors.accent)

            Text(project.isClosingProject ? "Saving..." : "Loading...")
                .font(SB.Typo.body)
                .foregroundStyle(SB.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SB.Colors.background)
        .accessibilityIdentifier("editor_loading_placeholder")
    }

    private var exportButton: some View {
        Group {
            if project.isExporting {
                HStack(spacing: SB.Space.sm) {
                    ProgressView(value: project.exportProgress)
                        .tint(SB.Colors.accent)
                        .frame(width: SB.Layout.exportProgressWidth)
                    Text("\(Int(project.exportProgress * 100))%")
                        .font(SB.Typo.mono)
                        .foregroundStyle(SB.Colors.textSecondary)
                }
            } else {
                SBPrimaryButton(title: "Export", icon: "square.and.arrow.up") {
                    exportPanelManager.show(project: project)
                }
                .accessibilityIdentifier("editor_export_button")
            }
        }
    }
}
