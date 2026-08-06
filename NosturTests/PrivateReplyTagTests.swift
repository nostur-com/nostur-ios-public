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
}
