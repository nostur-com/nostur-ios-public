//import SwiftUI
//import UIKit
//import AVFoundation
//import NukeVideo
//
//struct UIVideoViewer: UIViewRepresentable {
//    @State var asset:AVAsset
//    @State var videoPlayerView:NosturVideoPlayerView
//    @Binding var isPlaying:Bool
//    @Binding var isMuted:Bool
//    
//    init(asset: AVAsset, isPlaying:Binding<Bool>, isMuted:Binding<Bool>) {
//        self.videoPlayerView = NosturVideoPlayerView()
//        self.asset = asset
//        _isPlaying = isPlaying
//        _isMuted = isMuted
//    }
//    
//    func makeUIView(context: Context) -> UIView {
//        videoPlayerView.asset = asset
//        //        videoPlayerView.playerLayer.player?.
//        if (isPlaying) {
//            do { try AVAudioSession.sharedInstance().setActive(true) }
//            catch { }
//            videoPlayerView.play()
//            videoPlayerView.playerLayer.player?.isMuted = isMuted
//        }
//        else {
//            videoPlayerView.pause()
//        }
//        return videoPlayerView
//    }
//    
//    func updateUIView(_ uiView: UIView, context: Context) {
//        if (isPlaying) {
//            do { try AVAudioSession.sharedInstance().setActive(true) }
//            catch { }
//            if let currentTime = videoPlayerView.playerLayer.player?.currentTime(), currentTime.seconds > 0 {
//                videoPlayerView.playerLayer.player?.play()
//            }
//            else {
//                videoPlayerView.play()
//            }
//            videoPlayerView.playerLayer.player?.isMuted = isMuted
//        }
//        else {
//            videoPlayerView.pause()
//            videoPlayerView.playerLayer.player?.isMuted = true
//        }
//    }
//}
