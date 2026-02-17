import Foundation

@Observable
final class ProjectStore {
    private(set) var projects: [ProjectInfo] = []
    private let baseDirectory: URL

    private var catalogURL: URL {
        baseDirectory.appendingPathComponent("projects.json")
    }

    init(baseDirectory: URL? = nil) {
        let dir = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Screenboom", isDirectory: true)
        self.baseDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadCatalog()
    }

    // MARK: - Path Helpers

    func projectDirectory(for id: UUID) -> URL {
        baseDirectory
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func stateFileURL(for id: UUID) -> URL {
        projectDirectory(for: id).appendingPathComponent("state.json")
    }

    func thumbnailURL(for id: UUID) -> URL {
        projectDirectory(for: id).appendingPathComponent("thumbnail.jpg")
    }

    // MARK: - CRUD

    func add(_ info: ProjectInfo) {
        projects.append(info)
        let dir = projectDirectory(for: info.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sortAndSave()
    }

    func remove(_ id: UUID) {
        projects.removeAll { $0.id == id }
        let dir = projectDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
        saveCatalog()
    }

    func update(_ id: UUID, _ transform: (inout ProjectInfo) -> Void) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        transform(&projects[idx])
        sortAndSave()
    }

    func touchLastOpened(_ id: UUID) {
        update(id) { $0.lastOpenedAt = Date() }
    }

    // MARK: - Persistence

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogURL) else { return }
        projects = (try? JSONDecoder().decode([ProjectInfo].self, from: data)) ?? []
        projects.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func saveCatalog() {
        let data = try? JSONEncoder().encode(projects)
        try? data?.write(to: catalogURL, options: .atomic)
    }

    private func sortAndSave() {
        projects.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        saveCatalog()
    }

    // MARK: - Migration

    func migrateIfNeeded() {
        let legacyURL = baseDirectory.appendingPathComponent("project-state.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        let id = UUID()
        let dir = projectDirectory(for: id)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: legacyURL, to: stateFileURL(for: id))
        } catch {
            return
        }

        // Try to extract project name from the bookmark
        var name = "Imported Project"
        if let state = SavedState.load(from: legacyURL),
           let bookmark = state.sourceURLBookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                name = url.deletingPathExtension().lastPathComponent
                url.stopAccessingSecurityScopedResource()
            }
        }

        let info = ProjectInfo(id: id, name: name, createdAt: Date(), lastOpenedAt: Date())
        add(info)

        try? FileManager.default.removeItem(at: legacyURL)
    }
}
