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
//
//struct AnimatedGifViewX: View {
//    let gifData:Data
//    let width:CGFloat
//    let height:CGFloat
//    let contentMode:UIView.ContentMode
//    @State var isPlaying = false
//    
//    init(gifData: Data, width: CGFloat, height: CGFloat, contentMode: UIView.ContentMode = .scaleToFill, isPlaying: Bool = false) {
//        self.gifData = gifData
//        self.width = width
//        self.height = height
//        self.contentMode = contentMode
//        self.isPlaying = isPlaying
//    }
//    
//    var body: some View {
//        AnimatedGifViewInner(gifData: gifData, width: width, height: height, contentMode: contentMode, isPlaying: $isPlaying)
//            .onAppear {
//                isPlaying = true
//            }
//            .onDisappear {
//                isPlaying = false
//            }
//    }
//}
//
//struct AnimatedGifViewInner: UIViewRepresentable {
//    let gifData:Data
//    let width:CGFloat
//    let height:CGFloat
//    let contentMode:UIView.ContentMode
//    @Binding var isPlaying:Bool
//    
//    init(gifData: Data, width: CGFloat, height: CGFloat, contentMode: UIView.ContentMode = .scaleAspectFill, isPlaying:Binding<Bool>) {
//        self.gifData = gifData
//        self.width = width
//        self.height = height
//        self.contentMode = contentMode
//        _isPlaying = isPlaying
//    }
//
//    func makeUIView(context: Context) -> GIFImageView {
//        let imageView = GIFImageView(frame: CGRect(x: 0, y: 0, width: width, height: height))
//        imageView.contentMode = contentMode
//        imageView.setFrameBufferCount(100)
//        imageView.setShouldResizeFrames(true)
//        imageView.prepareForAnimation(withGIFData: gifData)
//        return imageView
//    }
//
//    func updateUIView(_ uiView: GIFImageView, context: Context) {
//        if isPlaying { 
//            uiView.startAnimatingGIF()
//        }
//        else {
//            uiView.stopAnimating()
//        }
////        uiView.animate(withGIFData: gifData, loopBlock:  {
////            print("It's animating!")
////        })
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
