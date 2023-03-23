//
//  VideoPlayerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    var videoURL: URL
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<VideoPlayerView>) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.delegate = context.coordinator
        playerViewController.player = player
        playerViewController.showsPlaybackControls = true
        playerViewController.entersFullScreenWhenPlaybackBegins = false
        playerViewController.exitsFullScreenWhenPlaybackEnds = true
        playerViewController.allowsPictureInPicturePlayback = true
        return playerViewController
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: UIViewControllerRepresentableContext<VideoPlayerView>) {
        // Add full screen and PiP support
    }
    
    func makeCoordinator() -> Coordinator {
            return Coordinator()
        }
        
        class Coordinator: NSObject, AVPlayerViewControllerDelegate {
            func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
                return false
            }
        }
}


struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            VideoPlayerView(videoURL: URL(string: "https://nostr.build/av/nostr.build_c7914ef0389a34aaece69f29d167da393d5129be2208fc86a86ade9ae4229c83.mov")!)
                    VideoPlayerView(videoURL: URL(string: "https://nostr.build/p/nb3487.mp4")!)
        }
    }
}
