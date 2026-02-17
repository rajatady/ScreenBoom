import Foundation

struct ProjectInfo: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var lastOpenedAt: Date
    var videoWidth: Int?
    var videoHeight: Int?
    var videoDurationSeconds: Double?
    var sourceFileName: String?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        videoDurationSeconds: Double? = nil,
        sourceFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.videoDurationSeconds = videoDurationSeconds
        self.sourceFileName = sourceFileName
    }
}
