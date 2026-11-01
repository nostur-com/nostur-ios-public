import Foundation
import CryptoKit

/// BUD-10 image references. Parsing is pure: no discovery or network work here.
struct BlossomURI: Equatable {
    static let pattern = #"\bblossom:[^\s<>\"`]+(?<![.,;!?)\]}])"#
    let hash: String
    let fileExtension: String
    let servers: [URL]
    let authors: [String]
    let size: Int?

    init?(_ value: String) {
        guard value.utf8.count <= 8192,
              value.hasPrefix("blossom:"),
              let components = URLComponents(string: value), components.fragment == nil else { return nil }
        let filename = components.path.split(separator: ".", omittingEmptySubsequences: false)
        guard filename.count == 2, Self.isHash(String(filename[0])),
              ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic"].contains(String(filename[1])) else { return nil }
        hash = String(filename[0])
        fileExtension = String(filename[1])
        let items = components.queryItems ?? []
        var servers: [URL] = []
        var authors: [String] = []
        var size: Int?
        for item in items {
            guard let value = item.value else { continue }
            switch item.name {
            case "xs":
                if servers.count < 4, let server = Self.serverURL(value), !servers.contains(server) { servers.append(server) }
            case "as":
                if authors.count < 2, Self.isHash(value), !authors.contains(value) { authors.append(value) }
            case "sz":
                guard size == nil, !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let count = Int(value), count > 0 else { return nil }
                size = count
            default: break
            }
        }
        self.servers = servers
        self.authors = authors
        self.size = size
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Keep Nostur's HTTPS-only automatic media policy. Hints name server roots.
    static func serverURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value.contains("://") ? value : "https://" + value),
              components.scheme == "https", let host = components.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              host.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 }),
              !host.allSatisfy({ $0.isNumber || $0 == "." }),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil else { return nil }
        components.host = host.lowercased()
        components.path = ""
        return components.url
    }

    func url(on server: URL) -> URL {
        server.appendingPathComponent("\(hash).\(fileExtension)")
    }

    func verify(_ data: Data) -> Bool {
        (size == nil || size == data.count) && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash
    }

    static func allowsAutomaticLoad(postAuthor: String?, accountPubkey: String?, following: Set<String>) -> Bool {
        guard let postAuthor, let accountPubkey else { return false }
        return postAuthor == accountPubkey || following.contains(postAuthor)
    }
}
