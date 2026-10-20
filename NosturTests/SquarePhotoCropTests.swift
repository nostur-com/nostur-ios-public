import Testing
import UIKit
import ImageIO
@testable import Nostur

struct SquarePhotoCropTests {
    @Test func boundsStaySquareAndInsideImage() {
        for size in [CGSize(width: 400, height: 200), CGSize(width: 200, height: 400)] {
            for zoom: CGFloat in [0.5, 1, 2, 8, 20] {
                for center in [CGPoint(x: -1, y: 2), CGPoint(x: 0.5, y: 0.5)] {
                    let rect = SquarePhotoCrop(zoom: zoom, center: center).rect(in: size)
                    #expect(rect.width == rect.height)
                    #expect(rect.minX >= 0 && rect.minY >= 0)
                    #expect(rect.maxX <= size.width && rect.maxY <= size.height)
                }
            }
        }
    }

    @Test func renderUsesSelectedPixelsAndRetainsOriginalForReediting() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        }
        let data = try #require(image.pngData())
        var original = PostedImageMeta(index: 3, data: data, type: .png, uniqueId: "original")
        original.altText = "Two colors"
        let edited = try #require(renderSquarePhoto(attachment: original, crop: SquarePhotoCrop(zoom: 2, center: CGPoint(x: 0.75, y: 0.5))))
        #expect(UIImage(data: edited.data)?.size == CGSize(width: 100, height: 100))
        try expectBlue(try #require(UIImage(data: edited.data)))
        #expect(edited.uniqueId != original.uniqueId)
        #expect(edited.altText == original.altText)
        #expect(edited.index == 3)
        #expect(edited.cropSourceData == data)
        let reset = try #require(renderSquarePhoto(attachment: edited, crop: SquarePhotoCrop()))
        #expect(UIImage(data: reset.data)?.size == CGSize(width: 200, height: 200))
        #expect(reset.cropSourceData == data)
        // Compare against a crop from the original to catch destructive re-editing.
        let direct = try #require(renderSquarePhoto(attachment: original, crop: SquarePhotoCrop()))
        #expect(reset.data == direct.data)
    }

    @Test func exifOrientationIsAppliedBeforeCropping() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let attachment = PostedImageMeta(index: 0, data: data as Data, type: .jpeg, uniqueId: "rotated")
        let result = try #require(renderSquarePhoto(attachment: attachment, crop: SquarePhotoCrop()))
        let output = try #require(UIImage(data: result.data))
        #expect(output.size == CGSize(width: 200, height: 200))
        #expect(output.imageOrientation == .up)
        let bottom = try #require(renderSquarePhoto(attachment: attachment, crop: SquarePhotoCrop(zoom: 2, center: CGPoint(x: 0.5, y: 0.75))))
        try expectBlue(try #require(UIImage(data: bottom.data)))
    }

    private func expectBlue(_ image: UIImage) throws {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try #require(image.cgImage), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] < 10 && pixel[1] < 10 && pixel[2] > 240)
    }

    @Test func invalidImageFailsWithoutReplacement() {
        let attachment = PostedImageMeta(index: 0, data: Data(), type: .jpeg, uniqueId: "invalid")
        #expect(renderSquarePhoto(attachment: attachment, crop: SquarePhotoCrop()) == nil)
    }
}
