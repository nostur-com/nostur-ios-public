import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class FeedLoadingPreviewTests: XCTestCase {
    func testFirstLoadHasVisibleRowsAtTheLeadingEdgeInLightAndDarkThemes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (dark, fullWidth) in [(false, true), (true, true), (false, false), (true, false)] {
            var theme = Theme()
            theme.id = dark ? "loading-test-dark" : "loading-test-light"
            theme.listBackground = dark ? .black : .white
            theme.background = theme.listBackground
            theme.lineColor = theme.listBackground
            theme.primary = dark ? .white : .black
            let content = FeedLoadingPreview(fullWidth: fullWidth) {
                Label("Photos", systemImage: "photo")
            }
            .environment(\.theme, theme)
            .environment(\.colorScheme, dark ? .dark : .light)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.frame = .init(x: 0, y: 0, width: 390, height: 700)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            window.layoutIfNeeded()

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Feed loading preview \(dark ? "dark" : "light") \(fullWidth ? "full width" : "compact")"
            attachment.lifetime = .keepAlways
            add(attachment)
            // The incoming page's leading strip is visible before its central
            // spinner/title. It must contain feed-shaped content, not a blank panel.
            XCTAssertGreaterThan(try visibleLeadingEdgePixels(in: image, dark: dark), 500)
        }
    }

    private func visibleLeadingEdgePixels(in image: UIImage, dark: Bool) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress,
                                                 width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: .init(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            var count = 0
            for y in 80..<(height - 40) {
                for x in 16..<60 {
                    let red = data[(y * width + x) * 4]
                    if dark ? red > 8 : red < 247 { count += 1 }
                }
            }
            return count
        }
    }
}
