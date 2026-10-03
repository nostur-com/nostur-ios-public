import Foundation
import Testing
@testable import Nostur

struct NIP19Tests {
    @Test func noteEncodingRejectsMissingOrMalformedIDs() {
        for id in ["", "24c54bfe", String(repeating: "g", count: 64), String(repeating: "a", count: 66)] {
            #expect(throws: (any Error).self) {
                try NIP19(prefix: "note", hexString: id)
            }
        }
    }

    @Test func parentNoteEncodingMatchesReportedEvent() throws {
        let id = "24c54bfe192a2e3af5b96a31ef3e33b788cb26fb904c7f4a79571bc02687b9df"
        #expect(try NIP19(prefix: "note", hexString: id).displayString == "note1ynz5hlse9ghr4adedgc7703nk7yvkfhmjpx87jne2uduqf58h80s7d06h0")
    }

    @Test func shareableIdentifierDecodesKindWithoutAlignmentAssumptions() throws {
        var tlvData = Data([0, 1, 0x61, 3, 4])
        tlvData.append(contentsOf: [0x00, 0x00, 0x75, 0x37])
        let encoded = Bech32().encode("naddr", values: tlvData, eightToFive: true)

        let identifier = try ShareableIdentifier(encoded)

        #expect(identifier.kind == 30_007)
    }

    @Test func shareableIdentifierRejectsInvalidKindLength() {
        let tlvData = Data([3, 3, 0x00, 0x00, 0x01])
        let encoded = Bech32().encode("nevent", values: tlvData, eightToFive: true)

        #expect(throws: (any Error).self) {
            try ShareableIdentifier(encoded)
        }
    }
}
