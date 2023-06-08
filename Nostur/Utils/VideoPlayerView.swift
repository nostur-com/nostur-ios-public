//
//  VideoPlayerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI
import AVKit
import AVFoundation

// SwiftUI video player
// Plays video from remote URL. Uses AVKit
struct VideoPlayerViewer: View {
    var videoURL: URL
    var width:CGFloat
    var height:CGFloat
    
    @State private var player: AVPlayer?
    @State private var playerController = AVPlayerViewController()
    @State private var isPlaying = false

    var body: some View {
        VStack {
            AVPlayerViewControllerRepresentable(controller: self.playerController)
                .frame(width: width, height: height)
        }
        .onAppear {
            self.player = AVPlayer(url: self.videoURL)
            self.playerController.player = self.player
        }
        .onDisappear {
            self.player?.pause()
        }
        .edgesIgnoringSafeArea(.all)
        .background(Color.black)
        .overlay(
                Button(action: {
                    if self.isPlaying {
                        self.player?.pause()
                        self.isPlaying = false
                    } else {
                        self.player?.play()
                        self.isPlaying = true
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .resizable()
                        .scaledToFit()
                        .padding(50)
                        .frame(width: width, height: height)
                }.opacity(isPlaying ? 0 : 1)
        )
    }
}

struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    var controller: AVPlayerViewController

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    }
}


struct AVP: UIViewControllerRepresentable {
    let player:AVPlayer
    let videoURL: URL
    let width:CGFloat
    let height:CGFloat
    let contentMode:UIView.ContentMode
    @Binding var isPlaying:Bool
    
    init(videoURL: URL, width: CGFloat, height: CGFloat, contentMode: UIView.ContentMode = .scaleAspectFill, isPlaying:Binding<Bool>) {
        self.player = AVPlayer(url: videoURL)
        self.videoURL = videoURL
        self.width = width
        self.height = height
        self.contentMode = contentMode
        _isPlaying = isPlaying
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.player = self.player
        playerViewController.showsPlaybackControls = true
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.delegate = context.coordinator
        playerViewController.player?.play()
        
        return playerViewController
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if (isPlaying) {
            self.player.play()
        }
        else {
            self.player.play()
        }
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var parent: AVP
        
        init(_ parent: AVP) {
            self.parent = parent
        }
    }
}

