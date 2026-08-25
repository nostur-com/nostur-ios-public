//
//  BlossomMediaRecovery.swift
//  Nostur
//

import Foundation
import NostrEssentials

enum BlossomMediaRecovery {
    private static let blossomListKind = 10063

    static func hash(from url: URL) -> String? {
        let filename = url.deletingPathExtension().lastPathComponent.lowercased()
        guard filename.count == 64,
              filename.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return filename
    }

    static func candidateURLs(
        originalURL: URL,
        hash: String,
        serverStrings: [String]
    ) -> [URL] {
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { return [] }

        let suffix = originalURL.pathExtension
        let filename = suffix.isEmpty ? hash : "\(hash).\(suffix)"
        var seen = Set<String>()

        return serverStrings.flatMap { serverString -> [URL] in
            guard var components = URLComponents(string: serverString),
                  components.scheme?.lowercased() == "https",
                  components.host != nil
            else { return [] }

            components.query = nil
            components.fragment = nil
            guard let serverURL = components.url else { return [] }

            // Blossom servers commonly accept both the original extension and the
            // canonical extensionless BUD-01 download path.
            return [filename, hash].compactMap { pathComponent in
                let candidate = serverURL.appendingPathComponent(pathComponent)
                guard candidate != originalURL,
                      seen.insert(candidate.absoluteString).inserted
                else { return nil }
                return candidate
            }
        }
    }

    static func candidateURLs(originalURL: URL, authorPubkey: String) async -> [URL] {
        guard let hash = hash(from: originalURL) else { return [] }
        let servers = await fetchServerList(authorPubkey: authorPubkey)
        return candidateURLs(originalURL: originalURL, hash: hash, serverStrings: servers)
    }

    static func fetchServerList(authorPubkey: String) async -> [String] {
        guard let response = try? await relayReq(
            Filters(authors: [authorPubkey], kinds: [blossomListKind], limit: 1),
            timeout: 4.5,
            debounceTime: 0.15,
            useOutbox: true
        ), let event = response.relayMessage?.event
        else { return [] }

        var seen = Set<String>()
        return servers(from: event.tags)
            .filter { seen.insert($0).inserted }
    }

    private static func servers(from tags: [NostrTag]) -> [String] {
        tags.compactMap { tag in
            guard tag.type == "server" else { return nil }
            let value = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }
}
