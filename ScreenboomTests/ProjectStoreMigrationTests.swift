import Testing
import Foundation
@testable import Screenboom

// MARK: - ProjectStore migration tests
// Covers: migrateIfNeeded with legacy file, migrateIfNeeded with no legacy file (no-op),
// migrateIfNeeded removes legacy file after migration.

@MainActor
struct ProjectStoreMigrationTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("screenboom-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func migrateIfNeededWithNoLegacyFileIsNoOp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        store.migrateIfNeeded()

        #expect(store.projects.isEmpty, "No migration should occur without legacy file")
    }

    @Test func migrateIfNeededMovesLegacyStateToProject() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a legacy state file
        let legacyURL = dir.appendingPathComponent("project-state.json")
        let legacyState = SavedState(
            sourceURLBookmark: nil, sourceURLPath: "/tmp/old-video.mp4",
            splitPoints: [2.5], segmentStates: [
                SavedState.SavedSegment(startTime: 0, endTime: 5, speed: 1.0, isEnabled: true),
            ],
            gradientColor1: [0.1, 0.1, 0.1], gradientColor2: [0.9, 0.9, 0.9],
            padding: 60, cornerRadius: 16, shadowRadius: 30, shadowOpacity: 0.5,
            outputWidth: 1920, outputHeight: 1080, playheadTime: 1.5, showThumbnails: nil,
            backgroundStyleJSON: nil, frameStyleJSON: nil,
            cursorEnabled: nil, cursorStyle: nil, cursorSize: nil,
            clickEffectEnabled: nil, clickEffectColor: nil, clickEffectMaxRadius: nil, clickEffectDuration: nil,
            autoZoomEnabled: nil, autoZoomLevel: nil, autoZoomSensitivity: nil, zoomRegions: nil
        )
        legacyState.write(to: legacyURL)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))

        let store = ProjectStore(baseDirectory: dir)
        store.migrateIfNeeded()

        // Should have one project now
        #expect(store.projects.count == 1)
        let project = store.projects[0]
        #expect(project.name == "Imported Project") // No bookmark to extract name from

        // State file should exist in the project directory
        let stateURL = store.stateFileURL(for: project.id)
        #expect(FileManager.default.fileExists(atPath: stateURL.path))

        // The migrated state should be loadable
        let loaded = SavedState.load(from: stateURL)
        #expect(loaded != nil)
        #expect(loaded?.splitPoints == [2.5])
        #expect(loaded?.sourceURLPath == "/tmp/old-video.mp4")

        // Legacy file should be removed
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func migrateIfNeededIsIdempotent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create legacy file
        let legacyURL = dir.appendingPathComponent("project-state.json")
        let state = SavedState(
            sourceURLBookmark: nil, sourceURLPath: nil,
            splitPoints: [], segmentStates: [],
            gradientColor1: [0, 0, 0], gradientColor2: [1, 1, 1],
            padding: 60, cornerRadius: 16, shadowRadius: 30, shadowOpacity: 0.5,
            outputWidth: 1920, outputHeight: 1080, playheadTime: 0, showThumbnails: nil,
            backgroundStyleJSON: nil, frameStyleJSON: nil,
            cursorEnabled: nil, cursorStyle: nil, cursorSize: nil,
            clickEffectEnabled: nil, clickEffectColor: nil, clickEffectMaxRadius: nil, clickEffectDuration: nil,
            autoZoomEnabled: nil, autoZoomLevel: nil, autoZoomSensitivity: nil, zoomRegions: nil
        )
        state.write(to: legacyURL)

        let store = ProjectStore(baseDirectory: dir)
        store.migrateIfNeeded()
        #expect(store.projects.count == 1)

        // Call again — legacy file is gone, should be no-op
        store.migrateIfNeeded()
        #expect(store.projects.count == 1, "Second migration should not add duplicate")
    }

    // MARK: - touchLastOpened

    @Test func touchLastOpenedUpdatesDateAndReorders() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)

        let oldDate = Date(timeIntervalSince1970: 1000000)
        let info1 = ProjectInfo(id: UUID(), name: "Older", createdAt: oldDate, lastOpenedAt: oldDate)
        let info2 = ProjectInfo(id: UUID(), name: "Newer", createdAt: Date(), lastOpenedAt: Date())

        store.add(info1)
        store.add(info2)

        // info2 should be first (more recent)
        #expect(store.projects[0].name == "Newer")

        // Touch info1 — should move to front
        store.touchLastOpened(info1.id)
        #expect(store.projects[0].id == info1.id, "Touched project should be first")
    }
}
