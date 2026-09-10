import Foundation
import Testing
@testable import Nostur

struct NIP19Tests {
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
