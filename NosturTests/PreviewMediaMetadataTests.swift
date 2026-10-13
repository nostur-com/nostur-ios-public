import CryptoKit
import Nuke
import Testing
import UIKit
@testable import Nostur

struct PreviewMediaMetadataTests {
    @Test func missingOriginalImageBytesDoesNotHashResizedImage() {
        let metadata = PreviewMediaMetadata.image(data: nil, renderedImage: testImage(), dimensions: CGSize(width: 100, height: 200))
        #expect(metadata.hash == nil)
        #expect(metadata.blurHash != nil)
        #expect(metadata.size == CGSize(width: 100, height: 200))
    }

    private func testImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        }
    }
}
