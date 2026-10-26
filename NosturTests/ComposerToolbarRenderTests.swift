import NavigationBackport
import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@available(iOS 27.0, *)
@MainActor
final class ComposerToolbarRenderTests: XCTestCase {
    func testPostRemainsVisibleWhenDraftBecomesNonempty() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousDraft = Drafts.shared.draft
        let previousMentions = Drafts.shared.draftMentions
        defer {
            Drafts.shared.draft = previousDraft
            Drafts.shared.draftMentions = previousMentions
        }
        let model = NewPostModel()
        let host = UIHostingController(rootView: NBNavigationStack {
            Entry(vm: model, photoPickerShown: .constant(false), videoPickerShown: .constant(false), gifSheetShown: .constant(false), cameraSheetShown: .constant(false), onDismiss: {}, replyToKind: nil, kind: .textNote, showAudioRecorder: .constant(false))
        }
        .composerNavigationStackCompat()
        .environment(\.theme, Theme(accent: .red))
        .environment(\.colorScheme, .light))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true }
        for (index, text) in ["", "Draft", "Draft with more text"].enumerated() {
            model.typingTextModel.text = text
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Composer toolbar, draft state \(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Only Post uses the injected red accent. Its disabled circle is
            // neutral; an enabled draft must show a filled accent button.
            let pixels = try pixelCounts(inTrailingThirdOf: image)
            if text.isEmpty {
                XCTAssertGreaterThan(pixels.neutral, 500, "Disabled Post circle disappeared")
            } else {
                XCTAssertGreaterThan(pixels.red, 500, "Primary Post button disappeared after editing")
            }
        }
    }

    private func pixelCounts(inTrailingThirdOf image: UIImage) throws -> (red: Int, neutral: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            var redCount = 0
            var neutralCount = 0
            for y in 0..<height {
                for x in (width * 2 / 3)..<width {
                    let offset = (y * width + x) * 4
                    let red = Int(data[offset])
                    let green = Int(data[offset + 1])
                    let blue = Int(data[offset + 2])
                    if red > green + 40 && red > blue + 40 {
                        redCount += 1
                    }
                    if max(red, green, blue) - min(red, green, blue) < 10 && red < 245 {
                        neutralCount += 1
                    }
                }
            }
            return (redCount, neutralCount)
        }
    }
}
