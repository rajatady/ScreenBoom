import Foundation
import AVFoundation
import CoreGraphics

protocol ProjectStateStoreProtocol {
    func loadState(from url: URL) -> SavedState?
    func saveState(_ state: SavedState, to url: URL)
}

protocol ExportServiceProtocol {
    func export(
        asset: AVAsset,
        enabledSegments: [Segment],
        sourceSize: CGSize,
        exportSettings: FrameRenderer.Settings,
        cursorOverlayState: CursorOverlayState?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}
