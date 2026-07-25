//
//  ProfileImageSafety.swift
//  Nostur
//

import Foundation
import ImageIO

enum ProfileImageSafety {
    struct Policy {
        let maximumDimension: Int
        let maximumPixelCount: Int64
        let maximumAnimatedFrameCount: Int
        let maximumAnimatedPixelCount: Int64

        static let profilePicture = Policy(
            maximumDimension: 4_096,
            maximumPixelCount: 16_777_216,
            maximumAnimatedFrameCount: 300,
            maximumAnimatedPixelCount: 150_000_000
        )
        static let banner = Policy(
            maximumDimension: 8_192,
            maximumPixelCount: 67_108_864,
            maximumAnimatedFrameCount: 300,
            maximumAnimatedPixelCount: 200_000_000
        )
        static let badge = Policy(
            maximumDimension: 4_096,
            maximumPixelCount: 16_777_216,
            maximumAnimatedFrameCount: 200,
            maximumAnimatedPixelCount: 100_000_000
        )
        static let post = Policy(
            maximumDimension: 12_000,
            maximumPixelCount: 100_000_000,
            maximumAnimatedFrameCount: 300,
            maximumAnimatedPixelCount: 250_000_000
        )
        static let emoji = Policy(
            maximumDimension: 1_024,
            maximumPixelCount: 1_048_576,
            maximumAnimatedFrameCount: 100,
            maximumAnimatedPixelCount: 25_000_000
        )
    }

    /// Gifu expands GIF frames while preparing animation. Bound that work
    /// before handing it the downloaded bytes.
    static func isSafeAnimatedImage(_ data: Data, policy: Policy) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0, frameCount <= policy.maximumAnimatedFrameCount,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = integerValue(properties[kCGImagePropertyPixelWidth]),
              let height = integerValue(properties[kCGImagePropertyPixelHeight]),
              width > 0, height > 0,
              width <= policy.maximumDimension, height <= policy.maximumDimension else {
            return false
        }

        let (pixelsPerFrame, pixelOverflow) = Int64(width).multipliedReportingOverflow(by: Int64(height))
        let (totalPixels, totalOverflow) = pixelsPerFrame.multipliedReportingOverflow(by: Int64(frameCount))
        return !pixelOverflow
            && pixelsPerFrame <= policy.maximumPixelCount
            && !totalOverflow
            && totalPixels <= policy.maximumAnimatedPixelCount
    }

    private static func integerValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
