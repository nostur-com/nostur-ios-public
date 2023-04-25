//
//  ImageTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/04/2023.
//

import SwiftUI

struct ImageTest: View {
    @State var uiImage:UIImage?
    var body: some View {
        VStack {
            if let uiImage {
                Image(uiImage: uiImage)
            }
        }
        .task {
            if let asset = UIImage(named: "ImageTest") {
                uiImage = profilePic(asset)
            }
            else if let asset = UIImage(named: "NosturLogo") {
                uiImage = profilePic(asset)
            }
        }
    }
}

struct ImageTest_Previews: PreviewProvider {
    static var previews: some View {
        ImageTest()
    }
}

// Create a profile pic, preserving aspect ratio, circle, resize to 100x100
func profilePic(_ image: UIImage, preserveAspect:Bool = true) -> UIImage? {
    let size = CGSize(width: 100, height: 100)
    let rect = CGRect(origin: CGPoint.zero, size: size)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
//    let path = UIBezierPath(ovalIn: rect)
//    path.addClip()
    if preserveAspect {
        let aspect = image.size.width / image.size.height
        let width = size.width
        let height = width / aspect
        let x = CGFloat(0)
        let y = (size.height - height) / 2
        let drawRect = CGRect(x: x, y: y, width: width, height: height)
        image.draw(in: drawRect)
    } else {
        image.draw(in: rect)
    }
    let result = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return result
}

func letsSee() -> UIImage {
    let uiImage = UIImage(named: "ImageTest")!
    let maxDimension: CGFloat = 150.0 * UIScreen.main.scale // maximum width or height
    
    // Scale to fill, if widht or height is less than maxDimension, scale up
    
    
    // If the least of height/width is bigger than maxDimension, scale down to maxDimension
    let scale = min(maxDimension / uiImage.size.width, maxDimension / uiImage.size.height)
    let pictureSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)

    let squareWidth = min(uiImage.size.width * scale, uiImage.size.height * scale)
    let squareSize = CGSize(width: squareWidth, height: squareWidth)

    let renderer = UIGraphicsImageRenderer(size: squareSize)
    let scaledImage = renderer.image { _ in
        uiImage.draw(in: CGRect(origin: CGPoint(x: -Int(pictureSize.width/2), y: -Int(pictureSize.height/2)), size: squareSize))
    }
    
    return scaledImage
}
