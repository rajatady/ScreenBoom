import SwiftUI

struct ContentView: View {
    @Bindable var project: Project
    var store: ProjectStore
    @Namespace private var heroAnimation

    private var showEditor: Bool {
        project.currentProjectID != nil && project.asset != nil
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
    }

    private var editorView: some View {
        HSplitView {
            VStack(spacing: 0) {
                // Toolbar — glass-backed
                HStack {
                    SBSecondaryButton(title: "Back", icon: "chevron.left", compact: true) {
                        project.closeProject()
                    }
                    Spacer()
                }
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.sm)
                .background(.ultraThinMaterial)

                VideoPreviewView(project: project)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .matchedGeometryEffect(id: "hero-\(project.currentProjectID ?? UUID())", in: heroAnimation)

                Divider()

                TimelineView(project: project)
                    .frame(height: project.hasCursorData ? 240 : 200)
            }

            ControlsPanel(project: project)
                .frame(width: 280)
        }
    }
}
