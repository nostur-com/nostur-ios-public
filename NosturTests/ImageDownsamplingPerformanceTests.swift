import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Nuke
@testable import Nostur

/// Opt-in benchmark: run this class alone, with parallel testing disabled.
/// Measures uncached decoding/processing, not downloads or scrolling performance.
final class ImageDownsamplingPerformanceTests: XCTestCase {
    private var jpeg = Data()
    private var png = Data()

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Generate fixtures before measurement; no network or user photos involved.
        try autoreleasepool {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
                bytesPerRow: 4000 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            for y in stride(from: 0, to: 3000, by: 40) {
                for x in stride(from: 0, to: 4000, by: 40) {
                    context.setFillColor(CGColor(
                        red: CGFloat((x * 13 + y * 7) % 251) / 250,
                        green: CGFloat((x * 3 + y * 17) % 251) / 250,
                        blue: CGFloat((x * 19 + y * 11) % 251) / 250, alpha: 1
                    ))
                    context.fill(CGRect(x: x, y: y, width: 40, height: 40))
                }
            }
            let image = try XCTUnwrap(context.makeImage())
            jpeg = try encode(image, type: .jpeg)
            png = try encode(image, type: .png)
        }
    }

    func testJPEGFeedCurrent() { benchmark(data: jpeg, avatar: false, downsample: false) }
    func testJPEGFeedDownsampled() { benchmark(data: jpeg, avatar: false, downsample: true) }
    func testJPEGAvatarCurrent() { benchmark(data: jpeg, avatar: true, downsample: false) }
    func testJPEGAvatarDownsampled() { benchmark(data: jpeg, avatar: true, downsample: true) }
    func testPNGFeedCurrent() { benchmark(data: png, avatar: false, downsample: false) }
    func testPNGFeedDownsampled() { benchmark(data: png, avatar: false, downsample: true) }

    private func benchmark(data: Data, avatar: Bool, downsample: Bool) {
        // Explicit pixels make both paths identical regardless of simulator scale.
        let size = avatar ? CGSize(width: 150, height: 150) : CGSize(width: 1200, height: 900)
        let mode: ImageProcessingOptions.ContentMode = avatar ? .aspectFill : .aspectFit
        let processor = ImageProcessors.Resize(
            size: size, unit: .pixels, contentMode: mode, crop: avatar, upscale: avatar
        )
        let thumbnail = ImageRequest.ThumbnailOptions(size: size, unit: .pixels, contentMode: mode)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            for _ in 0..<8 {
                autoreleasepool {
                    do {
                        XCTAssertTrue(ProfileImageSafety.isSafeAnimatedImage(
                            data, policy: avatar ? .profilePicture : .post
                        ))
                        let decoded: UIImage
                        if downsample {
                            // The same thumbnail helper used by Nuke's default decoder.
                            decoded = try XCTUnwrap(thumbnail.makeThumbnail(with: data))
                        } else {
                            decoded = try ImageDecoders.Default().decode(data).image
                        }
                        let output = try XCTUnwrap(processor.process(decoded))
                        let bitmap = try XCTUnwrap(output.cgImage)
                        XCTAssertEqual(bitmap.width, Int(size.width))
                        XCTAssertEqual(bitmap.height, Int(size.height))
                    } catch {
                        XCTFail("Image processing failed: \(error)")
                    }
                }
            }
        }
    }

    private func encode(_ image: CGImage, type: UTType) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
