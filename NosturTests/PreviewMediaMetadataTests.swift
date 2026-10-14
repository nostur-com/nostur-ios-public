import CryptoKit
import Nuke
import Testing
import UIKit
@testable import Nostur

struct PreviewMediaMetadataTests {
    @Test func missingOriginalImageBytesDoesNotHashResizedImage() {
        let metadata = PreviewMediaMetadata.image(data: nil, dimensions: CGSize(width: 100, height: 200))
        #expect(metadata.hash == nil)
        #expect(metadata.blurHash == nil)
        #expect(metadata.size == CGSize(width: 100, height: 200))
    }

}
