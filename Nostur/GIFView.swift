//
//  GIFView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/03/2023.
//

import SwiftUI
import UIKit
import FLAnimatedImage

struct AnimatedGifView: UIViewRepresentable {
    let animatedView = FLAnimatedImageView()
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
    
    func makeUIView(context: UIViewRepresentableContext<AnimatedGifView>) -> UIView {
        let view = UIView()
//        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        
        view.contentMode = contentMode
        
        let gif = FLAnimatedImage(animatedGIFData: gifData)
        let animatedView = FLAnimatedImageView()
        animatedView.contentMode = contentMode
        animatedView.animatedImage = gif
        animatedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animatedView)
        
        NSLayoutConstraint.activate([
            animatedView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            animatedView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            animatedView.widthAnchor.constraint(equalTo: view.widthAnchor),
            animatedView.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<AnimatedGifView>) {
    }
}

//struct GIFView_Previews: PreviewProvider {
//    static var previews: some View {
//        GIFView()
//    }
//}
