import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Nostur

@MainActor
struct DMMediaPasteTests {
    @Test func mediaPastePreservesDraftAndUsesFirstAttachment() {
        let editor = MediaPasteTextView()
        editor.text = "Existing draft"
        editor.selectedRange = NSRange(location: 8, length: 5)
        let image = NSItemProvider(item: Data([1, 2, 3]) as NSData, typeIdentifier: UTType.png.identifier)
        let video = NSItemProvider(item: Data([4, 5, 6]) as NSData, typeIdentifier: UTType.mpeg4Movie.identifier)
        let text = NSItemProvider(object: "Text alternative" as NSString)
        var pastedTypes: [UTType] = []
        editor.onPasteMedia = { provider, type in
            #expect(provider === image)
            pastedTypes.append(type)
        }

        editor.paste(itemProviders: [text, image, video])

        #expect(pastedTypes == [.png])
        #expect(editor.text == "Existing draft")
        #expect(editor.selectedRange == NSRange(location: 8, length: 5))
    }

    @Test func ordinaryTextPasteUsesCurrentSelection() async throws {
        let editor = MediaPasteTextView()
        editor.text = "Hello draft"
        editor.selectedRange = NSRange(location: 6, length: 5)
        var mediaWasPasted = false
        editor.onPasteMedia = { _, _ in mediaWasPasted = true }
        editor.paste(itemProviders: [NSItemProvider(object: "world" as NSString)])

        let deadline = Date().addingTimeInterval(2)
        while editor.text == "Hello draft", Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(editor.text == "Hello world")
        #expect(!mediaWasPasted)
    }

    @Test func textAndWebURLsRemainText() {
        let text = NSItemProvider(object: "Hello" as NSString)
        let url = NSItemProvider(object: NSURL(string: "https://example.com/image.png")!)
        #expect(MediaPasteTextView.mediaType(for: text) == nil)
        #expect(MediaPasteTextView.mediaType(for: url) == nil)
    }

    @Test func mediaFormatsKeepTheirMIMETypes() {
        for type in [UTType.gif, .jpeg, .png, .quickTimeMovie, .mpeg4Movie, .mp3] {
            let provider = NSItemProvider(item: Data([1]) as NSData, typeIdentifier: type.identifier)
            #expect(MediaPasteTextView.mediaType(for: provider)?.preferredMIMEType == type.preferredMIMEType)
        }
    }

    @Test func copiedUIImageProvidesReadableImageFile() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        let provider = NSItemProvider(object: image)
        let type = try #require(MediaPasteTextView.mediaType(for: provider))
        #expect(type.preferredMIMEType?.hasPrefix("image/") == true)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                do {
                    let url = try #require(url)
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.cgImage?.width == image.cgImage?.width)
        #expect(decoded.cgImage?.height == image.cgImage?.height)
    }
}
