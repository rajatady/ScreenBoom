import Foundation

struct ProjectDependencies {
    let stateStore: any ProjectStateStoreProtocol
    let exportService: any ExportServiceProtocol

    static let live = ProjectDependencies(
        stateStore: FileProjectStateStore(),
        exportService: CompositionExportService()
    )
}

final class AppContainer {
    let projectStore: ProjectStore
    let projectDependencies: ProjectDependencies

    init(projectStore: ProjectStore, projectDependencies: ProjectDependencies) {
        self.projectStore = projectStore
        self.projectDependencies = projectDependencies
    }

    static func live(baseDirectory: URL? = nil) -> AppContainer {
        AppContainer(
            projectStore: ProjectStore(baseDirectory: baseDirectory),
            projectDependencies: .live
        )
    }

    func makeProject() -> Project {
        Project(dependencies: projectDependencies)
    }
}
