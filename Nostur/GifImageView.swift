//
//  GifImageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2023.
//

import SwiftUI
import UIKit
import Gifu

struct AnimatedGifView: UIViewRepresentable {
    let gifData:Data
    let width:CGFloat
    let height:CGFloat
    let contentMode:UIView.ContentMode
    
    init(gifData: Data, width: CGFloat, height: CGFloat, contentMode: UIView.ContentMode = .scaleAspectFill) {
        self.gifData = gifData
        self.width = width
        self.height = height
        self.contentMode = contentMode
    }

    func makeUIView(context: Context) -> GIFImageView {
        let imageView = GIFImageView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        imageView.contentMode = contentMode
        imageView.setShouldResizeFrames(true)
        imageView.animate(withGIFData: gifData)
        return imageView
    }

    func updateUIView(_ uiView: GIFImageView, context: Context) {
//        uiView.animate(withGIFData: gifData, loopBlock:  {
//            print("It's animating!")
//        })
    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    class Coordinator: NSObject {
//        var parent: AnimatedGifView
//
//        init(_ parent: AnimatedGifView) {
//            self.parent = parent
//        }
//    }
}
