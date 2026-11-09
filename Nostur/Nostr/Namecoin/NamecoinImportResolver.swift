//
//  NamecoinImportResolver.swift
//  Nostur
//
//  Resolves the ifa-0001 §"import" item of a Namecoin Domain Name Object,
//  recursively merging values from imported names into the importing
//  object before the caller extracts fields like `nostr.names`.
//
//  Spec: https://github.com/namecoin/proposals/blob/master/ifa-0001.md
//
//  Behaviour summary (matches the canonical implementation in amethyst's
//  quartz/commonMain):
//
//   - If the root JSON object has no `import` key, return it unchanged
//     (zero extra I/O — non-import records pay no cost).
//   - Four shorthand forms for the `import` value:
//       "import": "d/foo"                  → [["d/foo", ""]]
//       "import": ["d/foo"]                → [["d/foo", ""]]
//       "import": ["d/foo", "sel"]         → [["d/foo", "sel"]]
//       "import": [["d/foo","sel"], ...]   canonical, as-is
//   - Selector walks the imported value's `map` tree DNS-rightmost-first,
//     with exact label > "*" wildcard > "" default per level.
//   - Importer-wins merge: keys on the importer override imported keys,
//     and a JSON `null` on the importer suppresses the imported key.
//   - Multiple imports merge left-to-right (later overrides earlier),
//     then the importer is stacked on top of the accumulator.
//   - Recursion budget defaults to 4 (ifa-0001 minimum). Deeper chains
//     are truncated; importer's own fields still apply.
//   - Cycle protection via a visited-set keyed on `name|selector`.
//   - Lenient I/O: a failed fetch / malformed JSON is treated as `{}`
//     so transient ElectrumX hiccups don't kill resolution.
//   - The `import` key is stripped from the final merged result.
//

import Foundation

public enum NamecoinImportResolver {
    /// The minimum recursion depth ifa-0001 requires implementations to support.
    public static let defaultMaxDepth: Int = 4

    /// Async name lookup. Returns the raw value JSON string of the named
    /// record, or `nil` if the name does not exist / could not be fetched.
    /// Failures are absorbed by the resolver — never propagated.
    public typealias NameValueFetcher = @Sendable (_ namecoinName: String) async -> String?

    /// Expand all `import` items in `root` (and recursively in imported
    /// objects) up to `maxDepth` levels deep, returning a single merged
    /// object dictionary with no `import` key.
    ///
    /// If `root` has no `import` key, it is returned unchanged.
    public static func expandImports(
        root: [String: Any],
        maxDepth: Int = defaultMaxDepth,
        fetcher: NameValueFetcher
    ) async -> [String: Any] {
        var visited = Set<String>()
        return await expandRecursive(
            obj: root,
            fetcher: fetcher,
            budgetRemaining: maxDepth,
            visited: &visited
        )
    }

    // MARK: - Recursive expansion

    private static func expandRecursive(
        obj: [String: Any],
        fetcher: NameValueFetcher,
        budgetRemaining: Int,
        visited: inout Set<String>
    ) async -> [String: Any] {
        // No `import` key → passthrough, zero extra I/O.
        guard obj.keys.contains("import") else { return obj }
        let importItem = obj["import"] as Any

        guard let operations = parseImportItem(importItem) else {
            // Malformed import value: drop the key, keep everything else.
            return removeImportKey(obj)
        }
        if operations.isEmpty || budgetRemaining <= 0 {
            return removeImportKey(obj)
        }

        // Walk imports left-to-right. Spec is silent on multi-import
        // precedence; we follow the common-sense rule that LATER imports
        // override EARLIER ones in the same array. The whole accumulator
        // still loses to the importing object on top of all of it.
        var accumulator: [String: Any] = [:]
        for op in operations {
            let visitKey = "\(op.name)|\(op.selector)"
            if visited.contains(visitKey) { continue }
            visited.insert(visitKey)
            defer { visited.remove(visitKey) }

            let importedRaw = await fetcher(op.name)
            guard let raw = importedRaw,
                  let importedRoot = tryParseObject(raw),
                  let selectorView = applySelector(root: importedRoot, selector: op.selector)
            else { continue }

            let expanded = await expandRecursive(
                obj: selectorView,
                fetcher: fetcher,
                budgetRemaining: budgetRemaining - 1,
                visited: &visited
            )
            accumulator = mergeImporterWins(importer: expanded, imported: accumulator)
        }

        // Finally merge the importing object on top, removing its `import` key.
        let withoutImport = removeImportKey(obj)
        return mergeImporterWins(importer: withoutImport, imported: accumulator)
    }

    // MARK: - Merge

    /// Merge with importer-wins semantics: every key in `importer` stays
    /// as-is (including `NSNull`, which suppresses the imported counterpart
    /// per ifa-0001); keys present only in `imported` are added.
    private static func mergeImporterWins(
        importer: [String: Any],
        imported: [String: Any]
    ) -> [String: Any] {
        if imported.isEmpty { return importer }
        if importer.isEmpty { return imported }
        var out = imported
        for (k, v) in importer {
            out[k] = v
        }
        return out
    }

    // MARK: - Selector

    /// Walk the imported object's `map` tree to the node addressed by
    /// `selector` (DNS dotted). Empty selector returns `root` unchanged.
    ///
    /// Resolution rules per ifa-0001 §"map":
    ///   - Exact label match wins.
    ///   - `*` matches any single label.
    ///   - `""` is the default for the current level when no other match
    ///     applies.
    ///   - A non-object child terminates the walk with `nil`.
    private static func applySelector(
        root: [String: Any],
        selector: String
    ) -> [String: Any]? {
        if selector.isEmpty { return root }
        // Selector is DNS-dotted: leftmost label is most-specific. The
        // `map` tree is rooted at the parent and nests inwards toward the
        // leaf, so we walk labels right-to-left.
        let labels = selector
            .split(separator: ".", omittingEmptySubsequences: true)
            .map(String.init)
            .reversed()
        if labels.isEmpty { return root }

        var current: [String: Any] = root
        for label in labels {
            guard let map = current["map"] as? [String: Any] else { return nil }
            let child: [String: Any]?
            if let exact = map[label] as? [String: Any] {
                child = exact
            } else if let wildcard = map["*"] as? [String: Any] {
                child = wildcard
            } else if let fallback = map[""] as? [String: Any] {
                child = fallback
            } else {
                child = nil
            }
            guard let next = child else { return nil }
            current = next
        }
        return current
    }

    // MARK: - Parsing

    private struct ImportOp {
        let name: String
        /// DNS dotted, may be empty. Preserved as written.
        let selector: String
    }

    /// Parse the value of an `import` item into a flat list of `ImportOp`
    /// descriptors. Returns `nil` if the value is malformed.
    ///
    /// Accepted shapes (in order of preference):
    ///   - canonical: `[["d/foo"], ["d/bar","sub"]]`
    ///   - shorthand bare string: `"d/foo"` → one op, no selector
    ///   - shorthand single-array: `["d/foo"]` → one op, no selector
    ///   - shorthand pair-array: `["d/foo","sub"]` → one op with selector
    private static func parseImportItem(_ item: Any) -> [ImportOp]? {
        if let str = item as? String {
            let trimmed = str.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            return [ImportOp(name: trimmed, selector: "")]
        }
        guard let arr = item as? [Any] else { return nil }
        if arr.isEmpty { return [] }

        // Distinguish array-of-arrays (canonical) from array-of-strings (shorthand).
        if arr.first is [Any] {
            var ops: [ImportOp] = []
            for entry in arr {
                guard let inner = entry as? [Any] else { continue }
                if let op = opFromArray(inner) { ops.append(op) }
            }
            return ops
        }
        // Shorthand: ["name"] or ["name","selector"].
        if let op = opFromArray(arr) {
            return [op]
        }
        return []
    }

    private static func opFromArray(_ arr: [Any]) -> ImportOp? {
        guard !arr.isEmpty else { return nil }
        guard let rawName = arr[0] as? String else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }
        var selector = ""
        if arr.count >= 2 {
            guard let rawSel = arr[1] as? String else { return nil }
            selector = rawSel.trimmingCharacters(in: .whitespaces)
        }
        // Trailing dot is forbidden by spec; treat as malformed → no selector.
        if selector.hasSuffix(".") { return nil }
        return ImportOp(name: name, selector: selector)
    }

    // MARK: - Utilities

    private static func tryParseObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func removeImportKey(_ obj: [String: Any]) -> [String: Any] {
        guard obj.keys.contains("import") else { return obj }
        var out = obj
        out.removeValue(forKey: "import")
        return out
    }
}
