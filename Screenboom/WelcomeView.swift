import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Bindable var project: Project
    var store: ProjectStore
    var heroNamespace: Namespace.ID
    @State private var showingImporter = false
    @State private var editingID: UUID?
    @State private var editingName = ""
    @State private var deletingProject: ProjectInfo?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                projectsGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SBPageBackground() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            project.createProject(url: url, store: store)
            return true
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                project.createProject(url: url, store: store)
            }
        }
        .alert("Delete Project?", isPresented: Binding(
            get: { deletingProject != nil },
            set: { if !$0 { deletingProject = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let info = deletingProject {
                    withAnimation(SB.Anim.springSnappy) {
                        store.remove(info.id)
                    }
                }
                deletingProject = nil
            }
            Button("Cancel", role: .cancel) { deletingProject = nil }
        } message: {
            Text("This will permanently delete \"\(deletingProject?.name ?? "")\" and all its files.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SB.Space.xl) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

                VStack(spacing: SB.Space.sm) {
                    Text("Screenboom")
                        .font(SB.Typo.heroTitle)
                        .foregroundStyle(SB.Colors.textPrimary)

                    Text("Make your screen recordings look professional")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(SB.Colors.textSecondary)
                }
            }

            Spacer().frame(height: SB.Space.xxxl)

            VStack(spacing: SB.Space.md) {
                SBPrimaryButton(title: "Import Video", icon: "square.and.arrow.down", width: 180) {
                    showingImporter = true
                }
                SBSecondaryButton(title: "Record Screen", icon: "record.circle") {
                    openWindow(id: "recorder")
                }
            }

            Spacer()

            HStack(spacing: SB.Space.sm) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 11))
                Text("Or drag and drop a video file")
                    .font(SB.Typo.caption)
            }
            .foregroundStyle(SB.Colors.textTertiary)
            .padding(.bottom, SB.Space.xl)
        }
    }

    // MARK: - Projects Grid

    private var projectsGrid: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Projects")
                    .font(SB.Typo.pageTitle)
                    .foregroundStyle(SB.Colors.textPrimary)

                Spacer()

                HStack(spacing: SB.Space.sm) {
                    SBSecondaryButton(title: "Import", icon: "square.and.arrow.down", compact: true) {
                        showingImporter = true
                    }
                    SBSecondaryButton(title: "Record", icon: "record.circle", compact: true) {
                        openWindow(id: "recorder")
                    }
                }
            }
            .padding(.horizontal, SB.Space.xxl)
            .padding(.top, SB.Space.xl)
            .padding(.bottom, SB.Space.lg)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: SB.Space.xl)],
                    spacing: SB.Space.xl
                ) {
                    ForEach(store.projects) { info in
                        ProjectCard(
                            info: info,
                            store: store,
                            heroNamespace: heroNamespace,
                            isEditing: editingID == info.id,
                            editingName: editingID == info.id ? $editingName : .constant(""),
                            onOpen: {
                                project.loadProject(info: info, store: store)
                            },
                            onStartRename: {
                                editingName = info.name
                                withAnimation(SB.Anim.springSnappy) {
                                    editingID = info.id
                                }
                            },
                            onCommitRename: {
                                let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    store.update(info.id) { $0.name = trimmed }
                                }
                                withAnimation(SB.Anim.springSnappy) {
                                    editingID = nil
                                }
                            },
                            onDelete: {
                                deletingProject = info
                            }
                        )
                    }
                }
                .padding(.horizontal, SB.Space.xxl)
                .padding(.vertical, SB.Space.lg)
            }
        }
    }
}

// MARK: - Project Card

private struct ProjectCard: View {
    let info: ProjectInfo
    let store: ProjectStore
    var heroNamespace: Namespace.ID
    var isEditing: Bool
    @Binding var editingName: String
    var onOpen: () -> Void
    var onStartRename: () -> Void
    var onCommitRename: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail with hover-reveal actions
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                    .matchedGeometryEffect(id: "hero-\(info.id)", in: heroNamespace)

                // Hover-reveal action buttons (like Airbnb's heart icon)
                if isHovered && !isEditing {
                    HStack(spacing: SB.Space.xs) {
                        SBIconButton(icon: "pencil", size: 26) {
                            onStartRename()
                        }
                        SBIconButton(icon: "trash", size: 26, destructive: true) {
                            onDelete()
                        }
                    }
                    .padding(SB.Space.sm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            // Info area
            VStack(alignment: .leading, spacing: SB.Space.xs + 2) {
                if isEditing {
                    TextField("Project name", text: $editingName)
                        .font(SB.Typo.bodyMedium)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .onSubmit { onCommitRename() }
                        .onAppear { isNameFocused = true }
                        .padding(.horizontal, -2)
                } else {
                    Text(info.name)
                        .font(SB.Typo.bodyMedium)
                        .foregroundStyle(SB.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: SB.Space.sm) {
                    if let w = info.videoWidth, let h = info.videoHeight {
                        SBChip(text: "\(w)\u{00D7}\(h)")
                    }
                    if let dur = info.videoDurationSeconds {
                        SBChip(text: sbFormatDuration(dur))
                    }
                }

                Text(info.lastOpenedAt, format: .relative(presentation: .named))
                    .font(SB.Typo.caption)
                    .foregroundStyle(SB.Colors.textTertiary)
            }
            .padding(.horizontal, SB.Space.lg)
            .padding(.vertical, SB.Space.md + 2)
        }
        .sbCard(hovered: isHovered)
        .onHover { hovering in
            withAnimation(SB.Anim.springSnappy) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onOpen()
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let url = store.thumbnailURL(for: info.id)
        if FileManager.default.fileExists(atPath: url.path),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [SB.Colors.surface, SB.Colors.surfaceRaised],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "film")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(SB.Colors.textTertiary.opacity(0.4))
            }
        }
    }
}
