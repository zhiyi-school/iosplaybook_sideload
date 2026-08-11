import AVKit
import SwiftUI

struct VideoPlayerSheet: View {
    let recording: BroadcastRecording

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: recording.url))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(recording.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
