//
//  NamecoinScriptParsingTests.swift
//  NosturTests
//
//  Unit tests for the Namecoin scriptPubKey parser used to extract
//  (name, value) pairs from on-chain name transactions.
//
//  These tests are wire-format level and fully offline. They guard against
//  regressions in support for OP_NAME_FIRSTUPDATE (0x52) — the *first*
//  transaction in any newly-registered Namecoin name's lifetime. Before
//  the fix, the parser only matched OP_NAME_UPDATE (0x53) and silently
//  returned nil for any name that had never been re-updated.
//

import Foundation
import Testing
@testable import Nostur

struct NamecoinScriptParsingTests {

    /// Build a minimal-push (`<len> <bytes>`) PUSHDATA blob for payloads <0x4c bytes.
    private static func push(_ bytes: [UInt8]) -> [UInt8] {
        precondition(bytes.count < 0x4c, "test helper only handles small pushes")
        return [UInt8(bytes.count)] + bytes
    }

    private static func push(_ s: String) -> [UInt8] {
        push(Array(s.utf8))
    }

    // MARK: - OP_NAME_UPDATE (0x53) — sanity check

    @Test func parsesNameUpdateScript() throws {
        let name = "d/mstrofnone"
        let value = #"{"nostr":{"pubkey":"43185edecb675892824b1a37a57f3e407fbde2eda7201a3829b8cf4ba7c5b4f0"}}"#

        // <OP_NAME_UPDATE> <push name> <push value> OP_2DROP OP_DROP OP_RETURN
        var script: [UInt8] = [0x53]
        script.append(contentsOf: Self.push(name))
        script.append(contentsOf: Self.push(value))
        script.append(contentsOf: [0x6d, 0x75, 0x6a])

        let parsed = ElectrumXClient.parseNameScript(script)
        #expect(parsed != nil)
        #expect(parsed?.0 == name)
        #expect(parsed?.1 == value)
    }

    // MARK: - OP_NAME_FIRSTUPDATE (0x52) — the regression this test guards

    /// FIRSTUPDATE wire shape:
    ///   <OP_NAME_FIRSTUPDATE> <push name> <push rand> <push value>
    ///   OP_2DROP OP_2DROP <address_script>
    ///
    /// The `rand` push is the 8-byte randomness committed in the prior
    /// `name_new` tx. Parsers MUST skip it; otherwise the value field is
    /// mis-interpreted as the random salt and the real value goes unread.
    @Test func parsesNameFirstupdateScript() throws {
        let name = "d/mstrofnone"
        let rand: [UInt8] = [0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe]
        let value = #"{"nostr":{"pubkey":"43185edecb675892824b1a37a57f3e407fbde2eda7201a3829b8cf4ba7c5b4f0","relays":["wss://relay.testls.bit/","wss://relay.nostr.wine/"]}}"#

        var script: [UInt8] = [0x52]
        script.append(contentsOf: Self.push(name))
        script.append(contentsOf: Self.push(rand))
        script.append(contentsOf: Self.push(value))
        // OP_2DROP OP_2DROP OP_RETURN (the trailing address script — opaque to the parser)
        script.append(contentsOf: [0x6d, 0x6d, 0x6a])

        let parsed = ElectrumXClient.parseNameScript(script)
        #expect(parsed != nil, "FIRSTUPDATE script must parse — pre-fix this returned nil")
        #expect(parsed?.0 == name)
        #expect(parsed?.1 == value, "value must come from the third push, not the rand salt")
    }

    // MARK: - Unknown leading opcode is rejected

    @Test func rejectsNonNameOpScript() throws {
        // OP_0 push — not a name op.
        let script: [UInt8] = [0x00] + Self.push("d/whatever") + Self.push("{}")
        #expect(ElectrumXClient.parseNameScript(script) == nil)
    }

    @Test func rejectsEmptyScript() throws {
        #expect(ElectrumXClient.parseNameScript([]) == nil)
    }
}
