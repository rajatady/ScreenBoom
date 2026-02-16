import SwiftUI
import AVKit

struct VideoPreviewView: NSViewRepresentable {
    let project: Project

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.player = project.player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== project.player {
            nsView.player = project.player
        }
    }
}
