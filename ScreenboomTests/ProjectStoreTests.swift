import Testing
import Foundation
@testable import Screenboom

struct ProjectStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - ProjectInfo

    @Test func projectInfoRoundTrip() throws {
        let info = ProjectInfo(
            id: UUID(),
            name: "Demo Recording",
            videoWidth: 1920,
            videoHeight: 1080,
            videoDurationSeconds: 42.5,
            sourceFileName: "demo.mp4"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ProjectInfo.self, from: data)

        #expect(decoded == info)
        #expect(decoded.videoWidth == 1920)
        #expect(decoded.videoHeight == 1080)
        #expect(decoded.videoDurationSeconds == 42.5)
        #expect(decoded.sourceFileName == "demo.mp4")
    }

    @Test func projectInfoNilOptionalsRoundTrip() throws {
        let info = ProjectInfo(name: "Bare Project")
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ProjectInfo.self, from: data)

        #expect(decoded == info)
        #expect(decoded.videoWidth == nil)
        #expect(decoded.videoHeight == nil)
        #expect(decoded.videoDurationSeconds == nil)
        #expect(decoded.sourceFileName == nil)
    }

    @Test func projectInfoForwardCompatibility() throws {
        // Simulate JSON from an older version that lacks optional fields
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Old Project","createdAt":0,"lastOpenedAt":0}
        """
        let decoded = try JSONDecoder().decode(ProjectInfo.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.name == "Old Project")
        #expect(decoded.videoWidth == nil)
        #expect(decoded.videoHeight == nil)
        #expect(decoded.videoDurationSeconds == nil)
        #expect(decoded.sourceFileName == nil)
    }

    // MARK: - ProjectStore CRUD

    @Test func addAndRetrieve() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let info = ProjectInfo(name: "Test")
        store.add(info)

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.id == info.id)
        #expect(store.projects.first?.name == "Test")
    }

    @Test func remove() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let info = ProjectInfo(name: "ToDelete")
        store.add(info)
        #expect(store.projects.count == 1)

        store.remove(info.id)
        #expect(store.projects.isEmpty)
    }

    @Test func touchLastOpenedReorders() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let older = ProjectInfo(name: "Older", lastOpenedAt: Date(timeIntervalSinceNow: -100))
        let newer = ProjectInfo(name: "Newer", lastOpenedAt: Date(timeIntervalSinceNow: -10))
        store.add(older)
        store.add(newer)

        // newer should be first (more recent)
        #expect(store.projects.first?.id == newer.id)

        // Touch the older one — it should move to front
        store.touchLastOpened(older.id)
        #expect(store.projects.first?.id == older.id)
    }

    @Test func updatePreservesData() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let info = ProjectInfo(name: "Original")
        store.add(info)

        store.update(info.id) { $0.name = "Updated"; $0.videoWidth = 3840 }

        let updated = store.projects.first { $0.id == info.id }
        #expect(updated?.name == "Updated")
        #expect(updated?.videoWidth == 3840)
        #expect(updated?.id == info.id) // ID unchanged
    }

    @Test func sortingInvariant() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let a = ProjectInfo(name: "A", lastOpenedAt: Date(timeIntervalSinceNow: -300))
        let b = ProjectInfo(name: "B", lastOpenedAt: Date(timeIntervalSinceNow: -200))
        let c = ProjectInfo(name: "C", lastOpenedAt: Date(timeIntervalSinceNow: -100))

        // Add in non-sorted order
        store.add(b)
        store.add(a)
        store.add(c)

        // Should always be most-recent-first
        #expect(store.projects.map(\.name) == ["C", "B", "A"])
    }

    // MARK: - Path Derivation

    @Test func stateFileURLPathDerivation() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let id = UUID()
        let expected = dir
            .appendingPathComponent("projects")
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("state.json")

        #expect(store.stateFileURL(for: id) == expected)
    }

    @Test func thumbnailURLPathDerivation() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProjectStore(baseDirectory: dir)
        let id = UUID()
        let expected = dir
            .appendingPathComponent("projects")
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("thumbnail.jpg")

        #expect(store.thumbnailURL(for: id) == expected)
    }

    // MARK: - Catalog Persistence

    @Test func catalogPersistence() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = ProjectStore(baseDirectory: dir)
        let infoA = ProjectInfo(name: "Alpha")
        let infoB = ProjectInfo(name: "Beta")
        store1.add(infoA)
        store1.add(infoB)

        // New store from same directory should load the same data
        let store2 = ProjectStore(baseDirectory: dir)
        #expect(store2.projects.count == 2)
        #expect(store2.projects.contains { $0.id == infoA.id })
        #expect(store2.projects.contains { $0.id == infoB.id })
    }
}
