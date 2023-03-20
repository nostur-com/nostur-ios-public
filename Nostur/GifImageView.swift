////
////  GifImageView.swift
////  Nostur
////
////  Created by Fabian Lachman on 20/03/2023.
////
//
//import SwiftUI
//import UIKit
//import Gifu
////import Nuke
////import NukeUI
////import NukeExtensions
////import NukeVideo
////import AVKit
////import GIFImageView
//
////struct NosturVideo: UIViewRepresentable {
////    let asset:AVAsset
////    let width:CGFloat
////    let height:CGFloat
////
////    func makeUIView(context: Context) -> VideoPlayerView {
////        let videoView = VideoPlayerView()
////        videoView.frame = CGRect(x: 0, y: 0, width: width, height: height)
////        videoView.asset = asset
////        videoView.contentMode = .scaleAspectFit
////        videoView.play()
////        return videoView
////    }
////
////    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
//////        uiView.play()
////    }
//////
//////    func makeCoordinator() -> Coordinator {
//////        Coordinator(self)
//////    }
//////
//////    class Coordinator: NSObject {
//////        var parent: AnimatedGifView
//////
//////        init(_ parent: AnimatedGifView) {
//////            self.parent = parent
//////        }
//////    }
////}
//
//struct AnimatedGifView: UIViewRepresentable {
//    let gifData:Data
//    let width:CGFloat
//    let height:CGFloat
//
//    func makeUIView(context: Context) -> GIFImageView {
//        let imageView = GIFImageView(frame: CGRect(x: 0, y: 0, width: width, height: height))
//        imageView.contentMode = .scaleAspectFit
//        return imageView
//    }
//
//    func updateUIView(_ uiView: GIFImageView, context: Context) {
//        uiView.animate(withGIFData: gifData, loopBlock:  {
//            print("It's animating!")
//        })
//    }
////
////    func makeCoordinator() -> Coordinator {
////        Coordinator(self)
////    }
////
////    class Coordinator: NSObject {
////        var parent: AnimatedGifView
////
////        init(_ parent: AnimatedGifView) {
////            self.parent = parent
////        }
////    }
//}
//
//struct GIFImageViewWrapper: UIViewRepresentable {
//    let gifData:Data
//    let width:CGFloat
//    let height:CGFloat
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//    
//    func makeUIView(context: Context) -> GIFImageView {
//        let imageView = GIFImageView(frame: CGRect(x: 0, y: 0, width: width, height: height))
//        imageView.contentMode = .scaleAspectFit
////        imageView.backgroundColor = .clear
//        imageView.animate(withGIFData: gifData, loopBlock:  {
//            print("It's animating!")
//        })
//        return imageView
//    }
//    
//    func updateUIView(_ uiView: GIFImageView, context: Context) {
//    }
//    
//    class Coordinator: NSObject {
//        var parent: GIFImageViewWrapper
//        
//        init(_ parent: GIFImageViewWrapper) {
//            self.parent = parent
//        }
//    }
//}
//
////struct GifImageView_Previews: PreviewProvider {
////    static var previews: some View {
//////        GIFImageViewWrapper(gifData: "mugen")
//////                   .frame(width: 200, height: 100)
////    }
////}
