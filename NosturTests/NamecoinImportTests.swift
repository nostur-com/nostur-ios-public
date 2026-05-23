//
//  NamecoinImportTests.swift
//  NosturTests
//
//  Hermetic tests for `NamecoinImportResolver` and the import-aware
//  NIP-05 resolution path through `NamecoinResolver`.
//
//  No network: every "imported" name is served by an in-memory map keyed
//  by Namecoin name. The integration tests use a fake `IElectrumXClient`
//  to assert on the names actually queried.
//

import Foundation
import Testing
@testable import Nostur

// MARK: - Test helpers

/// Parse a JSON string into a `[String: Any]` for use as a resolver input.
private func parseObject(_ s: String) -> [String: Any] {
    let data = s.data(using: .utf8)!
    return try! JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as! [String: Any]
}

/// In-memory `IElectrumXClient` double. Tests register records by Namecoin
/// name; the client records every queried identifier for assertions.
private final class FakeElectrumXClient: IElectrumXClient, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: String] = [:]
    private(set) var queriedNames: [String] = []

    func register(_ name: String, value: String) {
        lock.lock(); defer { lock.unlock() }
        records[name] = value
    }

    func nameShowWithFallback(identifier: String, servers: [ElectrumXServer]) async throws -> NameShowResult? {
        lock.lock()
        queriedNames.append(identifier)
        let value = records[identifier]
        lock.unlock()
        guard let v = value else { return nil }
        return NameShowResult(name: identifier, value: v, txid: nil, height: nil)
    }
}

// MARK: - Unit tests: NamecoinImportResolver in isolation

struct NamecoinImportResolverTests {

    // 1. no `import` key → passthrough, no extra fetch
    @Test func passthroughWhenNoImport() async {
        let obj = parseObject(#"{"ip":"1.2.3.4"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { _ in
            Issue.record("fetcher must not be called for records without import")
            return nil
        }
        #expect((expanded["ip"] as? String) == "1.2.3.4")
        #expect(expanded["import"] == nil)
    }

    // 2. string shorthand `"d/foo"`
    @Test func stringShorthandMergesImported() async {
        let obj = parseObject(#"{"import":"d/lib","ip":"1.1.1.1"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib" ? #"{"ip":"9.9.9.9","nostr":{"names":{"_":"abc"}}}"# : nil
        }
        // Importer wins on `ip`; imported fills in `nostr.names`.
        #expect((expanded["ip"] as? String) == "1.1.1.1")
        let nostr = expanded["nostr"] as? [String: Any]
        let names = nostr?["names"] as? [String: Any]
        #expect((names?["_"] as? String) == "abc")
        #expect(expanded["import"] == nil)
    }

    // 3. array shorthand `["d/foo"]`
    @Test func arrayShorthandSingleName() async {
        let obj = parseObject(#"{"import":["d/lib"],"local":"keep"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib" ? #"{"only":"from-lib"}"# : nil
        }
        #expect((expanded["local"] as? String) == "keep")
        #expect((expanded["only"] as? String) == "from-lib")
    }

    // 4. array-with-selector shorthand `["d/foo","sel"]`
    @Test func pairArrayShorthandUsesSelector() async {
        let obj = parseObject(#"{"import":["d/lib","relay"]}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib"
                ? #"{"ip":"1.1.1.1","map":{"relay":{"ip":"7.7.7.7","tag":"selected"}}}"#
                : nil
        }
        // Selected map.relay → its contents merged at top; d/lib's top-level
        // ip (1.1.1.1) is NOT seen because we descended.
        #expect((expanded["ip"] as? String) == "7.7.7.7")
        #expect((expanded["tag"] as? String) == "selected")
    }

    // 5. canonical array-of-arrays
    @Test func canonicalArrayOfArraysProcessedInOrder() async {
        let obj = parseObject(#"{"import":[["d/a"],["d/b"]]}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            switch name {
            case "d/a": return #"{"ip":"10.0.0.1","tag":"from-a"}"#
            case "d/b": return #"{"ip":"10.0.0.2","extra":"from-b"}"#
            default: return nil
            }
        }
        // d/b is processed AFTER d/a, so its `ip` wins (later overrides earlier).
        #expect((expanded["ip"] as? String) == "10.0.0.2")
        #expect((expanded["tag"] as? String) == "from-a")
        #expect((expanded["extra"] as? String) == "from-b")
    }

    // 6. importer-wins on plain keys
    @Test func importerWinsOnPlainKeys() async {
        let obj = parseObject(#"{"import":"d/lib","ip":"1.1.1.1","extra":"local"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib" ? #"{"ip":"9.9.9.9","extra":"remote","only-imported":"yes"}"# : nil
        }
        #expect((expanded["ip"] as? String) == "1.1.1.1")
        #expect((expanded["extra"] as? String) == "local")
        #expect((expanded["only-imported"] as? String) == "yes")
    }

    // 7. null in importer suppresses imported key
    @Test func nullInImporterSuppressesImported() async {
        let obj = parseObject(#"{"import":"d/lib","ip":null}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib" ? #"{"ip":"9.9.9.9","other":"keep"}"# : nil
        }
        // Key is still present, but as NSNull — downstream code treats it
        // as absent (same observable outcome as removal).
        #expect(expanded["ip"] is NSNull)
        #expect((expanded["other"] as? String) == "keep")
    }

    // 8. depth-4 recursion happy path
    @Test func depthFourRecursionSupported() async {
        let obj = parseObject(#"{"import":"d/a"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            switch name {
            case "d/a": return #"{"import":"d/b","layer":"a"}"#
            case "d/b": return #"{"import":"d/c","layer":"b"}"#
            case "d/c": return #"{"import":"d/d","layer":"c"}"#
            case "d/d": return #"{"layer":"d","deep":"reached"}"#
            default: return nil
            }
        }
        #expect((expanded["layer"] as? String) == "a")
        #expect((expanded["deep"] as? String) == "reached")
    }

    // 9. depth-5 chain truncated at budget, importer's own fields kept
    @Test func recursionDeeperThanMaxDepthIsTruncated() async {
        let obj = parseObject(#"{"import":"d/a","local":"keep"}"#)
        let expanded = await NamecoinImportResolver.expandImports(
            root: obj,
            maxDepth: 1
        ) { name in
            switch name {
            case "d/a": return #"{"import":"d/b","tag":"from-a"}"#
            case "d/b": return #"{"tag":"from-b","leaf":"wont-show"}"#
            default: return nil
            }
        }
        #expect((expanded["tag"] as? String) == "from-a")
        #expect((expanded["local"] as? String) == "keep")
        #expect(expanded["leaf"] == nil)
    }

    // 10. lookup returns null → treated as `{}`
    @Test func failedLookupTreatedAsEmpty() async {
        let obj = parseObject(#"{"import":"d/missing","local":"survives"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { _ in nil }
        #expect((expanded["local"] as? String) == "survives")
        #expect(expanded["import"] == nil)
    }

    // 11. lookup throws → treated as `{}`
    //
    // Swift's NameValueFetcher signature is non-throwing (callers absorb
    // errors before returning `nil`). The wired NamecoinResolver catches
    // and converts thrown errors to `nil`; here we simulate the same.
    @Test func throwingLookupTreatedAsEmpty() async {
        let obj = parseObject(#"{"import":"d/oops","local":"keep"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { _ in
            // Simulate the production wrapper that catches and returns nil.
            return nil
        }
        #expect((expanded["local"] as? String) == "keep")
    }

    // 12. lookup returns malformed JSON → treated as `{}`
    @Test func malformedImportedJsonIsSkipped() async {
        let obj = parseObject(#"{"import":"d/broken","local":"keep"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/broken" ? "not valid json {{{" : nil
        }
        #expect((expanded["local"] as? String) == "keep")
    }

    // 13. malformed `import` value (number) → no-op
    @Test func malformedImportValueIsSkipped() async {
        let obj = parseObject(#"{"import":42,"local":"keep"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { _ in nil }
        #expect((expanded["local"] as? String) == "keep")
        #expect(expanded["import"] == nil)
    }

    // 14. cycle A→B→A protected
    @Test func cycleInImportsIsBroken() async {
        let obj = parseObject(#"{"import":"d/a","local":"top"}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            switch name {
            case "d/a": return #"{"import":"d/b","fromA":"yes"}"#
            case "d/b": return #"{"import":"d/a","fromB":"yes"}"#
            default: return nil
            }
        }
        #expect((expanded["local"] as? String) == "top")
        // At least one side of the cycle made it through; the call must
        // terminate without recursion blowing up.
        #expect(expanded["fromA"] != nil || expanded["fromB"] != nil)
    }

    // 15. multi-label selector descends `map` tree DNS-order
    @Test func multiLabelSelectorDescendsDnsOrder() async {
        let obj = parseObject(#"{"import":[["d/lib","a.b"]]}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib" ? #"{"map":{"b":{"map":{"a":{"value":"deep"}}}}}"# : nil
        }
        #expect((expanded["value"] as? String) == "deep")
    }

    // 16. wildcard fallback when exact label absent
    @Test func selectorFallsBackToWildcard() async {
        let obj = parseObject(#"{"import":["d/lib","ghost"]}"#)
        let expanded = await NamecoinImportResolver.expandImports(root: obj) { name in
            name == "d/lib" ? #"{"map":{"*":{"value":"wildcard"}}}"# : nil
        }
        #expect((expanded["value"] as? String) == "wildcard")
    }
}

// MARK: - Integration: NamecoinResolver follows import

struct NamecoinResolverImportIntegrationTests {

    // 17. bare NIP-05 `_@foo.bit` resolves across import
    // 18. named NIP-05 `alice@foo.bit` resolves across import
    @Test func nip05LookupFollowsImportForSharedNostrNames() async {
        // The real-world `testls.bit` deployment: the apex record at
        // `d/testls` is up against the 520-byte per-name limit and
        // delegates its `nostr.names` block to a sibling name via
        // `"import":"dd/testls"`. Without import support, NIP-05
        // resolution sees no `nostr` field at d/testls and fails.
        let client = FakeElectrumXClient()
        client.register("d/testls", value: #"{"import":"dd/testls","ip":"107.152.38.155"}"#)
        client.register("dd/testls", value: #"""
            {"nostr":{"names":{
                "_":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c",
                "m":"6cdebccabda1dfa058ab85352a79509b592b2bdfa0370325e28ec1cb4f18667d"
            }}}
            """#)
        let resolver = NamecoinResolver(
            client: client,
            lookupTimeoutSeconds: 5,
            serverListProvider: { [] }
        )

        let rootResult = await resolver.resolve("testls.bit")
        #expect(rootResult != nil, "bare testls.bit should resolve via import")
        #expect(rootResult?.pubkey == "460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c")

        let mResult = await resolver.resolve("m@testls.bit")
        #expect(mResult != nil, "m@testls.bit should resolve via import")
        #expect(mResult?.pubkey == "6cdebccabda1dfa058ab85352a79509b592b2bdfa0370325e28ec1cb4f18667d")

        #expect(client.queriedNames.contains("d/testls"))
        #expect(client.queriedNames.contains("dd/testls"))
    }

    // resolveDetailed success across import (companion of #17/#18)
    @Test func resolveDetailedReturnsSuccessWhenImportSuppliesNames() async {
        let client = FakeElectrumXClient()
        client.register("d/testls", value: #"{"import":"dd/testls"}"#)
        client.register("dd/testls", value: #"""
            {"nostr":{"names":{
                "m":"6cdebccabda1dfa058ab85352a79509b592b2bdfa0370325e28ec1cb4f18667d"
            }}}
            """#)
        let resolver = NamecoinResolver(
            client: client,
            lookupTimeoutSeconds: 5,
            serverListProvider: { [] }
        )
        let outcome = await resolver.resolveDetailed("m@testls.bit")
        switch outcome {
        case .success(let result):
            #expect(result.pubkey == "6cdebccabda1dfa058ab85352a79509b592b2bdfa0370325e28ec1cb4f18667d")
        default:
            Issue.record("expected .success, got \(outcome)")
        }
    }

    // resolveDetailed → noNostrField when import target lacks nostr
    @Test func resolveDetailedReturnsNoNostrFieldWhenImportLacksIt() async {
        let client = FakeElectrumXClient()
        client.register("d/testls", value: #"{"import":"dd/testls"}"#)
        client.register("dd/testls", value: #"{"ip":"1.2.3.4"}"#)
        let resolver = NamecoinResolver(
            client: client,
            lookupTimeoutSeconds: 5,
            serverListProvider: { [] }
        )
        let outcome = await resolver.resolveDetailed("testls.bit")
        switch outcome {
        case .noNostrField:
            #expect(Bool(true))
        default:
            Issue.record("expected .noNostrField, got \(outcome)")
        }
    }

    // 19. no-import record issues exactly one ElectrumX query (regression
    //     guard for the "zero extra cost" property).
    @Test func recordWithoutImportKeySkipsImportResolver() async {
        let client = FakeElectrumXClient()
        client.register("d/plain", value: #"""
            {"nostr":{"names":{
                "_":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c"
            }}}
            """#)
        let resolver = NamecoinResolver(
            client: client,
            lookupTimeoutSeconds: 5,
            serverListProvider: { [] }
        )
        let result = await resolver.resolve("plain.bit")
        #expect(result?.pubkey == "460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c")
        #expect(client.queriedNames == ["d/plain"], "no import means exactly one query")
    }

    // 20. importer-wins on `nostr.names` map
    @Test func importerWinsForNostrNames() async {
        // Importer declares its own `nostr.names.m`; imported value
        // declares a different one. Importer wins on the whole `nostr`
        // key (shallow merge per spec).
        let client = FakeElectrumXClient()
        client.register("d/testls", value: #"""
            {"import":"dd/testls",
             "nostr":{"names":{"m":"aaaa000000000000000000000000000000000000000000000000000000000001"}}}
            """#)
        client.register("dd/testls", value: #"""
            {"nostr":{"names":{"m":"bbbb000000000000000000000000000000000000000000000000000000000002"}}}
            """#)
        let resolver = NamecoinResolver(
            client: client,
            lookupTimeoutSeconds: 5,
            serverListProvider: { [] }
        )
        let result = await resolver.resolve("m@testls.bit")
        #expect(result?.pubkey == "aaaa000000000000000000000000000000000000000000000000000000000001")
    }

    // Companion: failed import does not break NIP-05 if names are local
    @Test func failedImportDoesNotBreakLocalNostrNames() async {
        let client = FakeElectrumXClient()
        client.register("d/testls", value: #"""
            {"import":"dd/missing",
             "nostr":{"names":{"_":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c"}}}
            """#)
        // dd/missing is intentionally NOT registered.
        let resolver = NamecoinResolver(
            client: client,
            lookupTimeoutSeconds: 5,
            serverListProvider: { [] }
        )
        let result = await resolver.resolve("testls.bit")
        #expect(result?.pubkey == "460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c")
    }
}
