import Foundation
import Testing
@testable import Nostur

struct IMetaContentElementTests {
    @Test func extensionlessImageURLUsesIMetaMimeType() {
        let url = "https://cdn.example.com/media/0123456789abcdef"
        let tag: FastTag = (
            "imeta",
            "url \(url)",
            "m image/jpeg",
            "dim 1200x800",
            nil, nil, nil, nil, nil, nil
        )

        let (elements, linkPreviewURLs, galleryItems) = NRContentElementBuilder.shared.buildElements(
            input: url,
            fastTags: [tag]
        )

        #expect(elements.count == 1)
        guard case .image(let image) = elements.first else {
            Issue.record("Expected the extensionless URL to be rendered as an image")
            return
        }
        #expect(image.url.absoluteString == url)
        #expect(image.dimensions == CGSize(width: 1200, height: 800))
        #expect(linkPreviewURLs.isEmpty)
        #expect(galleryItems.map(\.url.absoluteString) == [url])
    }

    @Test func extensionlessURLWithoutImageMimeTypeRemainsLinkPreview() {
        let url = "https://example.com/posts/0123456789abcdef"
        let tag: FastTag = (
            "imeta",
            "url \(url)",
            "m application/octet-stream",
            nil, nil, nil, nil, nil, nil, nil
        )

        let (elements, linkPreviewURLs, galleryItems) = NRContentElementBuilder.shared.buildElements(
            input: url,
            fastTags: [tag]
        )

        #expect(elements.count == 1)
        guard case .linkPreview(let parsedURL, _) = elements.first else {
            Issue.record("Expected a non-image URL to remain a link preview")
            return
        }
        #expect(parsedURL.absoluteString == url)
        #expect(linkPreviewURLs.map(\.absoluteString) == [url])
        #expect(galleryItems.isEmpty)
    }
}
