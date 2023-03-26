//
//  VideoPlayerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI
import AVKit
import AVFoundation

struct AVP: UIViewControllerRepresentable {
    let videoURL: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.allowsPictureInPicturePlayback = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        
    }
}

struct AVPW: UIViewControllerRepresentable {
    let player: AVPlayer

    init(videoURL: URL) {
        self.player = AVPlayer(playerItem: AVPlayerItem(url: videoURL))
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }
}

struct AVPlayerView: UIViewRepresentable {
    let videoURL: URL
    let player = AVPlayer()

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = view.bounds
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)

        player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    var videoURL: URL
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<VideoPlayerView>) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        let playerViewController = AVPlayerViewController()
//        playerViewController.delegate = context.coordinator
        playerViewController.player = player
        playerViewController.showsPlaybackControls = true
        playerViewController.entersFullScreenWhenPlaybackBegins = false
        playerViewController.exitsFullScreenWhenPlaybackEnds = true
        playerViewController.allowsPictureInPicturePlayback = true
        return playerViewController
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: UIViewControllerRepresentableContext<VideoPlayerView>) {
    }
    
//    func makeCoordinator() -> Coordinator {
//            return Coordinator()
//        }
//
//        class Coordinator: NSObject, AVPlayerViewControllerDelegate {
//            func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
//                return false
//            }
//        }
}


struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            VideoPlayerView(videoURL: URL(string: "https://nostr.build/av/nostr.build_c7914ef0389a34aaece69f29d167da393d5129be2208fc86a86ade9ae4229c83.mov")!)
                    VideoPlayerView(videoURL: URL(string: "https://nostr.build/p/nb3487.mp4")!)
        }
    }
}
