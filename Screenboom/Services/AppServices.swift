import Foundation
import AVFoundation

struct FileProjectStateStore: ProjectStateStoreProtocol {
    func loadState(from url: URL) -> SavedState? {
        SavedState.load(from: url)
    }

    func saveState(_ state: SavedState, to url: URL) {
        state.write(to: url)
    }
}

struct CompositionExportService: ExportServiceProtocol {
    func export(
        asset: AVAsset,
        enabledSegments: [Segment],
        sourceSize: CGSize,
        exportSettings: FrameRenderer.Settings,
        cursorOverlayState: CursorOverlayState?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard !enabledSegments.isEmpty else { return }

        let composition = CompositionEngine.buildComposition(asset: asset, segments: enabledSegments)

        var exportCursorState: CursorOverlayState?
        if let cursorState = cursorOverlayState {
            let remapTable = CompositionEngine.buildTimeRemapTable(segments: enabledSegments)
            exportCursorState = CursorOverlayEngine.remapForExport(state: cursorState, remapTable: remapTable)
        }

        let videoComp = FrameRenderer.makeVideoComposition(
            for: composition,
            sourceSize: sourceSize,
            settings: exportSettings,
            cursorOverlayState: exportCursorState
        )

        try await CompositionEngine.export(
            composition: composition,
            videoComposition: videoComp,
            outputSize: exportSettings.outputSize,
            to: outputURL,
            progress: progress
        )
    }
}
