//
//  UIVideoView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI
import UIKit
import AVFoundation
import NukeVideo

struct UIVideoViewer: UIViewRepresentable {
    @State var asset:AVAsset
    @State var videoPlayerView:VideoPlayerView
    @Binding var isPlaying:Bool
    
    init(asset: AVAsset, isPlaying:Binding<Bool>) {
        self.videoPlayerView = VideoPlayerView()
        self.asset = asset
        _isPlaying = isPlaying
    }
    
    func makeUIView(context: Context) -> UIView {
        videoPlayerView.asset = asset
        //        videoPlayerView.playerLayer.player?.
        if (isPlaying) {
            videoPlayerView.play()
            videoPlayerView.playerLayer.player?.isMuted = false
        }
        else {
            videoPlayerView.playerLayer.player?.pause()
        }
        return videoPlayerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if (isPlaying) {
            videoPlayerView.play()
            videoPlayerView.playerLayer.player?.isMuted = false
        }
        else {
            videoPlayerView.playerLayer.player?.pause()
            videoPlayerView.playerLayer.player?.isMuted = true
        }
    }
}
