//
//  ImageTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/04/2023.
//

import SwiftUI

struct ImageTest: View {
    @State var uiImage:UIImage?
    @State var uiImage2:UIImage?
    @State var uiImage3:UIImage?
    @State var uiImage4:UIImage?
    @State var uiImage5:UIImage?
    @State var uiImage6:UIImage?
    @State var uiImage7:UIImage?
    var body: some View {
        ScrollView {
            VStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                }
                if let uiImage2 {
                    Image(uiImage: uiImage2)
                }
                if let uiImage3 {
                    Image(uiImage: uiImage3)
                }
                if let uiImage4 {
                    Image(uiImage: uiImage4)
                }
                if let uiImage5 {
                    Image(uiImage: uiImage5)
                }
                if let uiImage6 {
                    Image(uiImage: uiImage6)
                }
                if let uiImage7 {
                    Image(uiImage: uiImage7)
                }
            }
        }
        .frame(maxWidth:.infinity, maxHeight:.infinity)
        .background(Color.gray)
        .task {
            if let asset = UIImage(named: "TestWide") {
                uiImage = profilePic(asset)
            }
            if let asset = UIImage(named: "TestLong") {
                uiImage2 = profilePic(asset)
            }
            if let asset = UIImage(named: "TestSmall") {
                uiImage3 = profilePic(asset)
            }
            if let asset = UIImage(named: "TestWideBig") {
                uiImage4 = profilePic(asset)
            }
            if let asset = UIImage(named: "TestLongBig") {
                uiImage5 = profilePic(asset)
            }
            if let asset = UIImage(named: "TestTooSmallWide") {
                uiImage6 = profilePic(asset)
            }
            if let asset = UIImage(named: "TestTooSmallLong") {
                uiImage7 = profilePic(asset)
            }
//            else if let asset = UIImage(named: "Test") {
//                uiImage = profilePic(asset)
//            }
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
    let SIDE:CGFloat = 150
    let size = CGSize(width: SIDE, height: SIDE)
//    let rect = CGRect(origin: CGPoint.zero, size: size)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    
    // Steps.
    // Take smallest of width or height
    // if below 100, upscale to 100
    if image.size.width < image.size.height && image.size.width < SIDE {
        // WIDTH IS TOO SMALL:
        let upscaleFactor = SIDE / image.size.width
        let newHeight = image.size.height * upscaleFactor
        let x = 0.0
        let y = -((newHeight-SIDE)/2).rounded(.down)
        let drawRect = CGRect(x: x, y: y, width: SIDE, height: newHeight)
        image.draw(in: drawRect)
    }
    else if image.size.height < image.size.width && image.size.height < SIDE {
        // HEIGHT IS TOO SMALL:
        let upscaleFactor = SIDE / image.size.height
        let newWidth = image.size.width * upscaleFactor
        let x = -((newWidth-SIDE)/2).rounded(.down)
        let y = 0.0
        let drawRect = CGRect(x: x, y: y, width: newWidth, height: SIDE)
        image.draw(in: drawRect)
    }
    else if image.size.width < image.size.height && image.size.width > SIDE {
        // WIDTH SMALLER THAN HEIGHT, BUT TOO BIG
        let downscaleFactor = image.size.width / SIDE
        let newHeight = image.size.height / downscaleFactor
        let x = 0.0
        let y = -((newHeight-SIDE)/2).rounded(.down)
        let drawRect = CGRect(x: x, y: y, width: SIDE, height: newHeight)
        image.draw(in: drawRect)
    }
    else if image.size.height < image.size.width && image.size.height > SIDE {
        // HEIGHT SMALLER THAN WIDTH, BUT TOO BIG
        let downscaleFactor = image.size.height / SIDE
        let newWidth = image.size.width / downscaleFactor
        let x = -((newWidth-SIDE)/2).rounded(.down)
        let y = 0.0
        let drawRect = CGRect(x: x, y: y, width: newWidth, height: SIDE)
        image.draw(in: drawRect)
    }
    else {
//        let aspect = image.size.width / image.size.height
        let x = 0.0
        let y = 0.0
        let width = SIDE
        let height = SIDE
        let drawRect = CGRect(x: x, y: y, width: width, height: height)
        image.draw(in: drawRect)
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
