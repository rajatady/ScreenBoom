import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var project: Project
    @State private var showingImporter = false

    var body: some View {
        Group {
            if project.asset != nil {
                editorView
            } else {
                importView
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                project.loadVideo(url: url)
            }
        }
    }

    var importView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Drop a video or click Import")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Import Video") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            project.loadVideo(url: url)
            return true
        }
    }

    var editorView: some View {
        HSplitView {
            VStack(spacing: 0) {
                VideoPreviewView(project: project)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                TimelineView(project: project)
                    .frame(height: 200)
            }

            ControlsPanel(project: project)
                .frame(width: 280)
        }
    }
}
