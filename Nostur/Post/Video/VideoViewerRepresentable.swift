//
//  VideoViewerRepresentable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/06/2023.
//

import SwiftUI
import AVKit

//struct VideoViewerRepresentable: UIViewControllerRepresentable {
//    
//    @State var asset:AVAsset
//    @Binding var isPlaying:Bool
//    @Binding var isMuted:Bool
////    @State var avpc:CustomPlayerViewController
//
//    func makeUIViewController(context: Context) -> AVPlayerViewController {
//        
//        let avpc = AVPlayerViewController()
//        let playerItem = AVPlayerItem(asset: asset)
//        let player = AVQueuePlayer(playerItem: playerItem)
//        
////        player.isMuted = true
////        player.preventsDisplaySleepDuringVideoPlayback = false
////        player.actionAtItemEnd = .pause
////        avpc.customView.playerLayer.player = player
////        avpc.customView.playerLayer.player?.play()
//
//        avpc.player = player
////        avpc.player?.play()
////        avpc.exitsFullScreenWhenPlaybackEnds = false
//        avpc.videoGravity = .resizeAspectFill
//        avpc.allowsPictureInPicturePlayback = true
//        avpc.delegate = context.coordinator
////        avpc.showsPlaybackControls = true
////        avpc.canStartPictureInPictureAutomaticallyFromInline = true
//        
////        avpc.view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
////        avpc.view.translatesAutoresizingMaskIntoConstraints = false
////        avpc.view.backgroundColor = UIColor.yellow // UIColor(named: "ListBackground")
//        let what = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
//        what.backgroundColor = UIColor.red
//        avpc.view.addSubview(what)
////        av
////        avpc.loadViewIfNeeded()
//        
////        NSLayoutConstraint.activate([
////            avpc.view.leadingAnchor.constraint(equalTo: avpc.customView.leadingAnchor),
////            avpc.view.trailingAnchor.constraint(equalTo: avpc.customView.trailingAnchor),
////            avpc.view.topAnchor.constraint(equalTo: avpc.customView.topAnchor), // Add this line
////            avpc.view.bottomAnchor.constraint(equalTo: avpc.customView.bottomAnchor)
////        ])
//
//        return avpc
//    }
//
//    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
//        if isPlaying {
//            do { try AVAudioSession.sharedInstance().setActive(true) }
//            catch { }
////            uiViewController.customView.playerLayer.player?.play()
//            uiViewController.player?.isMuted = false
//            uiViewController.entersFullScreenWhenPlaybackBegins = true
//            uiViewController.player?.play()
//        }
//        else {
//            uiViewController.player?.isMuted = true
////            if let currentTime = uiViewController.player?.currentTime(), currentTime > CMTime.zero {
//                uiViewController.player?.pause()
////            }
//        }
//    }
//
//    typealias UIViewControllerType = AVPlayerViewController
//    
//    func makeCoordinator() -> Coordinator {
//        return Coordinator()
//    }
//
//    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
//        
//    }
//
//    init(asset: AVAsset, isPlaying:Binding<Bool>, isMuted:Binding<Bool>) {
//        do { try AVAudioSession.sharedInstance().setActive(true) }
//        catch { }
////        self.videoPlayerView = NosturVideoPlayerView()
//        self.asset = asset
//        _isPlaying = isPlaying
//        _isMuted = isMuted
//    }
//
//    
//}



//class CustomPlayerView: UIView {
//
//    private var _playerLayer: AVPlayerLayer?
//
//    public var playerLayer: AVPlayerLayer {
//        if let layer = _playerLayer {
//            return layer
//        }
//        let playerLayer = AVPlayerLayer()
//        self.layer.addSublayer(playerLayer)
//        playerLayer.frame = bounds
//        playerLayer.videoGravity = .resizeAspectFill
//        _playerLayer = playerLayer
//        return playerLayer
//    }
//
//    override func layoutSubviews() {
//        super.layoutSubviews()
//
//        CATransaction.begin()
//        CATransaction.setDisableActions(true)
//        _playerLayer?.frame = bounds
//        CATransaction.commit()
//    }
//}

//class CustomPlayerViewController: AVPlayerViewController {
//    let customView = CustomPlayerView()
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//
//        // Add constraints to position and size the custom view...
//        customView.translatesAutoresizingMaskIntoConstraints = false
//                customView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
//                customView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
//                customView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
//                customView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
//                customView.heightAnchor.constraint(equalToConstant: 200).isActive = true
//                customView.widthAnchor.constraint(equalToConstant: 200).isActive = true
//                customView.backgroundColor = .red
////                customView.player = player
//        view.addSubview(customView)
//    }
//}


//struct AVPlayerViewWrapper: UIViewControllerRepresentable {
//    private var asset: AVAsset
//
//    private var player: AVPlayer
//
//    init(asset:AVAsset) {
//        self.asset = asset
//        let pi = AVPlayerItem(asset: asset)
//        self.player = AVPlayer(playerItem: pi)
//    }
//
//    typealias UIViewControllerType = AVPlayerViewController
//
//    func makeCoordinator() -> Coordinator {
//        return Coordinator()
//    }
//
//    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
//
//    }
//
//    func makeUIViewController(context: Context) -> AVPlayerViewController {
//        let vc = AVPlayerViewController()
//        vc.player = player
//        vc.player?.isMuted = true
//        vc.videoGravity = .resizeAspect
//        vc.view.backgroundColor = UIColor.red
//        return vc
//    }
//
//    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
//        self.player.replaceCurrentItem(
//            with: AVPlayerItem(asset: asset))
//    }
//}

struct VideoViewurReprestable: UIViewRepresentable {
    typealias UIViewType = UIView
    
    @State var asset:AVAsset
    @Binding var isPlaying:Bool
    @Binding var isMuted:Bool
    
    init(asset: AVAsset, isPlaying:Binding<Bool>, isMuted:Binding<Bool>) {
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { }
        self.asset = asset
        _isPlaying = isPlaying
        _isMuted = isMuted
    }

    func makeUIView(context: Context) -> UIView {
        let avpc = AVPlayerViewController()
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        avpc.player = player
        avpc.exitsFullScreenWhenPlaybackEnds = false
        avpc.videoGravity = .resizeAspectFill
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        avpc.showsPlaybackControls = true
        avpc.canStartPictureInPictureAutomaticallyFromInline = true
        context.coordinator.avpc = avpc

        avpc.view.isUserInteractionEnabled = true
        return avpc.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the view if needed...
        uiView.isUserInteractionEnabled = true
        if isPlaying {
            do { try AVAudioSession.sharedInstance().setActive(true) }
            catch { }
            context.coordinator.avpc?.player?.isMuted = false
            context.coordinator.avpc?.player?.play()
        }
        else {
            context.coordinator.avpc?.player?.isMuted = true
            context.coordinator.avpc?.player?.pause()
        }
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var avpc:AVPlayerViewController?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
