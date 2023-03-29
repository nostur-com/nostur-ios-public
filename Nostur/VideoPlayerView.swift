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
    //    let player:AVPlayer
    let videoURL: URL
    let width:CGFloat
    let height:CGFloat
    let contentMode:UIView.ContentMode
    
    init(videoURL: URL, width: CGFloat, height: CGFloat, contentMode: UIView.ContentMode = .scaleAspectFill) {
        //        self.player = AVPlayer(url: videoURL)
        self.videoURL = videoURL
        self.width = width
        self.height = height
        self.contentMode = contentMode
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(url: videoURL)
        playerViewController.showsPlaybackControls = true
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.delegate = context.coordinator
        playerViewController.player?.play()
        
        
        return playerViewController
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    //    func makeUIView(context: Context) -> UIView {
    //        let playerView = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
    //        let player = AVPlayer(url: videoURL)
    //        let playerLayer = AVPlayerLayer(player: player)
    //        playerLayer.videoGravity = .resizeAspectFill
    //        playerLayer.frame = playerView.bounds
    //        playerView.layer.addSublayer(playerLayer)
    //
    //        player.play()
    //
    //        return playerView
    //    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var parent: AVP
        
        init(_ parent: AVP) {
            self.parent = parent
        }
    }
    
    //    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
    //        var parent: AVP
    //
    //        init(_ parent: AVP) {
    //            self.parent = parent
    //        }
    //    }
}


//struct AVP: View {
//    let videoURL: URL
//    var body: some View {
//        Text("video playback broken")
//    }
//}

//struct AVP: UIViewControllerRepresentable {
//    
//    var player: Player = Player()
//    let videoURL: URL
//    
//    func makeUIViewController(context: Context) -> UIViewController {
//        let viewController = UIViewController()
//        viewController.view.backgroundColor = .clear
//        
//        // Set up the player
//        player.url = videoURL
//        player.playerDelegate = context.coordinator
//        player.playbackDelegate = context.coordinator
//        player.fillMode = .resizeAspect
//        
//        viewController.addChild(player)
//        viewController.view.addSubview(player.view)
//        player.didMove(toParent: viewController)
//        
//        // Set player view's frame to match parent view's bounds
//        player.view.frame = viewController.view.bounds
//        
//        return viewController
//    }
//    
//    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(player: player)
//    }
//    
//    class Coordinator: NSObject, PlayerDelegate, PlayerPlaybackDelegate {
//        func playerReady(_ player: Player) {
//            
//        }
//        
//        func playerPlaybackStateDidChange(_ player: Player) {
//            
//        }
//        
//        func playerBufferingStateDidChange(_ player: Player) {
//            
//        }
//        
//        func playerBufferTimeDidChange(_ bufferTime: Double) {
//            
//        }
//        
//        func player(_ player: Player, didFailWithError error: Error?) {
//            
//        }
//        
//        func playerCurrentTimeDidChange(_ player: Player) {
//            
//        }
//        
//        func playerPlaybackWillStartFromBeginning(_ player: Player) {
//            
//        }
//        
//        func playerPlaybackDidEnd(_ player: Player) {
//            
//        }
//        
//        func playerPlaybackWillLoop(_ player: Player) {
//            
//        }
//        
//        func playerPlaybackDidLoop(_ player: Player) {
//            
//        }
//        
//        let player: Player
//        
//        init(player: Player) {
//            self.player = player
//        }
//        
//        // Implement PlayerDelegate and PlaybackDelegate methods as needed
//    }
//}

//struct AVPxx: UIViewRepresentable {
//    let player = Player()
//    let videoURL: URL
//    let width:CGFloat
//    let height:CGFloat
//    let contentMode:UIView.ContentMode
//    
//    init(videoURL: URL, width: CGFloat, height: CGFloat, contentMode: UIView.ContentMode = .scaleAspectFill) {
//        self.videoURL = videoURL
//        self.width = width
//        self.height = height
//        self.contentMode = contentMode
//    }
//    
//    func makeUIView(context: UIViewRepresentableContext<AVP>) -> UIView {
//        let view = UIView()
////        view.contentMode = contentMode
//        
//        player.url = videoURL
//        player.fillMode = .resizeAspect
////        player.playerView.contentMode = contentMode
////        player.playerView.translatesAutoresizingMaskIntoConstraints = false
//        player.playerDelegate = context.coordinator
//        player.playbackDelegate = context.coordinator
//        player.view.frame = view.bounds
//        view.addSubview(player.playerView)
//        player.didMove(toParentViewController: context.coordinator)
//                
//        
//        NSLayoutConstraint.activate([
//            player.playerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            player.playerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//            player.playerView.widthAnchor.constraint(equalTo: view.widthAnchor),
//            player.playerView.heightAnchor.constraint(equalTo: view.heightAnchor),
//        ])
//        
//    
//        return view
//    }
//    
//    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<AVP>) {
//    }
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(player: player)
//    }
//    
//    class Coordinator: NSObject, PlayerDelegate, PlayerPlaybackDelegate {
//        func playerReady(_ player: Player) {
//            
//        }
//        
//        func playerPlaybackStateDidChange(_ player: Player) {
//            
//        }
//        
//        func playerBufferingStateDidChange(_ player: Player) {
//            
//        }
//        
//        func playerBufferTimeDidChange(_ bufferTime: Double) {
//            
//        }
//        
//        func player(_ player: Player, didFailWithError error: Error?) {
//            
//        }
//        
//        func playerPlaybackDidLoop(_ player: Player) {
//            
//        }
//        
//        let player: Player
//        
//        init(player: Player) {
//            self.player = player
//        }
//        
//        // Implement PlayerDelegate and PlaybackDelegate methods as needed
//        public func playerPlaybackWillStartFromBeginning(_ player: Player) {
//        }
//        
//        public func playerPlaybackDidEnd(_ player: Player) {
//        }
//        
//        public func playerCurrentTimeDidChange(_ player: Player) {
//            //            let fraction = Double(player.currentTime) / Double(player.maximumDuration)
//            //            self._playbackViewController?.setProgress(progress: CGFloat(fraction), animated: true)
//        }
//        
//        public func playerPlaybackWillLoop(_ player: Player) {
//            //            self. _playbackViewController?.reset()
//        }
//    }
//}

struct AVPKAP: UIViewRepresentable {
    
    var player: Player = Player()
    let videoURL: URL
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // Set up the player
        player.url = videoURL
        player.playerDelegate = context.coordinator
        player.playbackDelegate = context.coordinator
        player.fillMode = .resizeAspect
        
        view.addSubview(player.view)
        
        // Set view's frame to parent view's bounds
        view.frame = CGRect(origin: .zero, size: player.view.intrinsicContentSize)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    //    func didMoveToSuperview(_ view: UIView) {
    //        player.view.frame = view.bounds
    //    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }
    
    class Coordinator: NSObject, PlayerDelegate, PlayerPlaybackDelegate {
        func playerReady(_ player: Player) {
            
        }
        
        func playerPlaybackStateDidChange(_ player: Player) {
            
        }
        
        func playerBufferingStateDidChange(_ player: Player) {
            
        }
        
        func playerBufferTimeDidChange(_ bufferTime: Double) {
            
        }
        
        func player(_ player: Player, didFailWithError error: Error?) {
            
        }
        
        func playerPlaybackDidLoop(_ player: Player) {
            
        }
        
        let player: Player
        
        init(player: Player) {
            self.player = player
        }
        
        // Implement PlayerDelegate and PlaybackDelegate methods as needed
        public func playerPlaybackWillStartFromBeginning(_ player: Player) {
        }
        
        public func playerPlaybackDidEnd(_ player: Player) {
        }
        
        public func playerCurrentTimeDidChange(_ player: Player) {
            //            let fraction = Double(player.currentTime) / Double(player.maximumDuration)
            //            self._playbackViewController?.setProgress(progress: CGFloat(fraction), animated: true)
        }
        
        public func playerPlaybackWillLoop(_ player: Player) {
            //            self. _playbackViewController?.reset()
        }
    }
}

struct AVPOLD: UIViewControllerRepresentable {
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
