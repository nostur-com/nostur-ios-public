import Testing
@testable import Nostur

struct ReportEventDetailsTests {
    private let pubkey = String(repeating: "a", count: 64)
    private let eventId = String(repeating: "b", count: 64)
    private let blobHash = String(repeating: "c", count: 64)

    @Test func parses_post_report_and_note() {
        let details = ReportEventDetails(
            fastTags: [
                ("e", eventId, "illegal", nil, nil, nil, nil, nil, nil, nil),
                ("p", pubkey, nil, nil, nil, nil, nil, nil, nil, nil)
            ],
            content: "  Additional context  "
        )

        #expect(details.target == .event(id: eventId, pubkey: pubkey))
        #expect(details.reasonDescription == "Illegal content")
        #expect(details.note == "Additional context")
    }

    @Test func parses_profile_report() {
        let details = ReportEventDetails(
            fastTags: [("p", pubkey, "impersonation", nil, nil, nil, nil, nil, nil, nil)],
            content: "\n"
        )

        #expect(details.target == .profile(pubkey: pubkey))
        #expect(details.reasonDescription == "Impersonation")
        #expect(details.note == nil)
    }

    @Test func blob_report_takes_reason_from_blob_tag() {
        let details = ReportEventDetails(
            fastTags: [
                ("x", blobHash, "malware", nil, nil, nil, nil, nil, nil, nil),
                ("e", eventId, "other", nil, nil, nil, nil, nil, nil, nil),
                ("p", pubkey, nil, nil, nil, nil, nil, nil, nil, nil)
            ],
            content: nil
        )

        #expect(details.target == .blob(hash: blobHash, eventId: eventId, pubkey: pubkey))
        #expect(details.reasonDescription == "Malicious software")
    }
}
