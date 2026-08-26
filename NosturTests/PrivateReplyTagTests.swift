import Foundation
import Testing
@testable import Nostur

struct PrivateReplyTagTests {
    @Test func private_reply_keeps_only_the_recipient_p_tag() {
        let recipient = String(repeating: "a", count: 64)
        let inheritedParticipant = String(repeating: "b", count: 64)
        let mentionedParticipant = String(repeating: "c", count: 64)

        var event = NEvent(content: "private reply")
        event.tags = [
            NostrTag(["p", inheritedParticipant]),
            NostrTag(["p", mentionedParticipant]),
            NostrTag(["p", recipient]),
            NostrTag(["e", "parent-event-id", "", "reply"]),
            NostrTag(["P", inheritedParticipant])
        ]

        let restricted = restrictPrivateReplyPTags(event, to: recipient)

        #expect(restricted.pTags() == [recipient])
        #expect(restricted.tags.contains(where: { $0.type == "e" }))
        #expect(restricted.tags.contains(where: { $0.type == "P" }))
    }

    @Test func private_reply_preview_is_marked_private() async {
        let isPrivate = await bg().perform {
            var event = NEvent(content: "private reply")
            event.id = String(repeating: "d", count: 64)
            let previewEvent = createPreviewEvent(event, isPrivate: true)
            defer { bg().delete(previewEvent) }

            return NRPost(event: previewEvent, withFooter: false).isPrivate
        }

        #expect(isPrivate)
    }

    @Test func encrypted_private_reply_imeta_contains_decryption_metadata() throws {
        let original = Data("private image bytes".utf8)
        let encrypted = try encryptFileForDM(data: original)
        let imeta = Imeta(
            url: "https://example.com/encrypted.bin",
            hash: encrypted.encryptedHash,
            mimeType: "image/jpeg",
            encryptedFile: encrypted
        )
        var parts = ["imeta", "url \(imeta.url)"]

        appendEncryptedIMetaFields(for: imeta, to: &parts)

        #expect(parts.contains("m image/jpeg"))
        #expect(parts.contains("decryption-key \(encrypted.key.hexEncodedString())"))
        #expect(parts.contains("decryption-nonce \(encrypted.nonce.hexEncodedString())"))
        #expect(parts.contains("ox \(encrypted.originalHash)"))
        #expect(try decryptFileFromDM(
            encryptedData: encrypted.encryptedData,
            key: encrypted.key,
            nonce: encrypted.nonce
        ) == original)

        let fastTag: FastTag = (
            "imeta",
            "url \(imeta.url)",
            "m image/jpeg",
            "decryption-key \(encrypted.key.hexEncodedString())",
            "decryption-nonce \(encrypted.nonce.hexEncodedString())",
            "ox \(encrypted.originalHash)",
            nil, nil, nil, nil
        )
        let parsed = iMetaFromFastTag(fastTag)?.encryptedFile
        #expect(parsed?.url == imeta.url)
        #expect(parsed?.mimeType == "image/jpeg")
        #expect(parsed?.decryptionKey == encrypted.key)
        #expect(parsed?.decryptionNonce == encrypted.nonce)
    }
}
