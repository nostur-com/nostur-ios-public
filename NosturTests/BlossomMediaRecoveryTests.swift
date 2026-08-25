import Foundation
import Testing
@testable import Nostur

struct BlossomMediaRecoveryTests {
    @Test func extractsBlossomHashFromFilename() {
        let hash = "7fc6066706b0283800d0bc86f87e394143dfbb6c9365504614e8585ae48631c9"
        let url = URL(string: "https://blossom.primal.net/\(hash).jpg")!

        #expect(BlossomMediaRecovery.hash(from: url) == hash)
    }

    @Test func rejectsNonHashFilename() {
        let url = URL(string: "https://example.com/images/photo.jpg")!
        #expect(BlossomMediaRecovery.hash(from: url) == nil)
    }

    @Test func buildsSafeDeduplicatedBlossomCandidates() {
        let hash = "7fc6066706b0283800d0bc86f87e394143dfbb6c9365504614e8585ae48631c9"
        let original = URL(string: "https://blossom.primal.net/\(hash).jpg")!
        let candidates = BlossomMediaRecovery.candidateURLs(
            originalURL: original,
            hash: hash,
            serverStrings: [
                "https://cdn.example.com",
                "https://cdn.example.com/",
                "http://insecure.example.com",
                "not a URL"
            ]
        )

        #expect(candidates.map(\.absoluteString) == [
            "https://cdn.example.com/\(hash).jpg",
            "https://cdn.example.com/\(hash)"
        ])
    }
}
