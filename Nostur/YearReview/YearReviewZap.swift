import Foundation
import CryptoKit

struct YearReviewZap: Codable, Equatable, Sendable {
    // Bump when receipt/provider validation rules change.
    static let validationVersion = 1
    let sender: String?
    let recipient: String
    let target: String?
    let millisats: Int64
    let paymentHash: String

    static func validate(_ receipt: YearReviewEvent, authorized: [String: Set<String>]) -> Self? {
        guard receipt.kind == 9735, receipt.verified(),
              receipt.tagValues("p").count == 1, let recipient = receipt.tagValues("p").first,
              authorized[recipient]?.contains(receipt.pubkey) == true,
              receipt.tagValues("description").count == 1, let description = receipt.tagValues("description").first,
              let requestData = description.data(using: .utf8),
              let request = try? JSONDecoder().decode(YearReviewEvent.self, from: requestData), request.kind == 9734,
              let signed = try? JSONDecoder().decode(NEvent.self, from: requestData), (try? signed.verified()) == true,
              request.tagValues("p") == [recipient], request.tagValues("e").count <= 1, request.tagValues("a").count <= 1,
              request.tagValues("e") == receipt.tagValues("e"), request.tagValues("a") == receipt.tagValues("a"),
              receipt.tagValues("bolt11").count == 1, let bolt = receipt.tagValues("bolt11").first,
              let invoice = invoice(bolt), invoice.descriptionHash == hex(Data(SHA256.hash(data: requestData))),
              request.tagValues("amount").count <= 1,
              request.tagValues("amount").first.map({ Int64($0) == invoice.millisats }) ?? true else { return nil }
        let anonymous = request.tags.contains { $0.first == "anon" }
        if !anonymous, let sender = receipt.tagValues("P").first, sender != request.pubkey { return nil }
        return Self(sender: anonymous ? nil : request.pubkey, recipient: recipient,
                    target: request.tagValues("a").first ?? request.tagValues("e").first,
                    millisats: invoice.millisats, paymentHash: invoice.paymentHash)
    }

    struct Invoice: Equatable {
        let millisats: Int64
        let paymentHash: String
        let descriptionHash: String
    }

    /// Exact integer amounts, checksum and hash fields; no floating-point rounding.
    static func invoice(_ value: String) -> Invoice? {
        guard value.utf8.count < 16_384, let (hrp, words) = Bech32().decode(value, limit: false),
              hrp.hasPrefix("lnbc"), words.count >= 111 else { return nil }
        var amount = String(hrp.dropFirst(4))
        var factor: Int64 = 100_000_000_000
        var divisor: Int64 = 1
        if let suffix = amount.last, !suffix.isNumber {
            amount.removeLast()
            switch suffix {
            case "m": factor = 100_000_000
            case "u": factor = 100_000
            case "n": factor = 100
            case "p": factor = 1; divisor = 10
            default: return nil
            }
        }
        guard let number = Int64(amount), number > 0 else { return nil }
        let product = number.multipliedReportingOverflow(by: factor)
        guard !product.overflow, product.partialValue % divisor == 0 else { return nil }
        let millisats = product.partialValue / divisor
        guard millisats > 0 else { return nil }
        let data = Array(words.dropLast(104))
        var cursor = 7
        var payment: String?
        var description: String?
        while cursor + 3 <= data.count {
            let type = data[cursor]
            let count = Int(data[cursor + 1]) * 32 + Int(data[cursor + 2])
            cursor += 3
            guard cursor + count <= data.count else { return nil }
            if type == 1 || type == 23 {
                guard count == 52, let bytes = Data(data[cursor..<cursor + count]).convertBits(fromBits: 5, toBits: 8, pad: false), bytes.count == 32 else { return nil }
                if type == 1 { guard payment == nil else { return nil }; payment = hex(bytes) }
                else { guard description == nil else { return nil }; description = hex(bytes) }
            }
            cursor += count
        }
        guard cursor == data.count, let payment, let description else { return nil }
        return Invoice(millisats: millisats, paymentHash: payment, descriptionHash: description)
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}

struct YearReviewZapProviderCheck: Codable, Sendable {
    let checkedAt: Date
    let endpoint: String?
    let signers: Set<String>

    func shouldRetry(endpoint: String?, signers: Set<String>, now: Date = .now) -> Bool {
        if let endpoint, endpoint != self.endpoint { return true }
        let age = now.timeIntervalSince(checkedAt)
        if age >= 24 * 60 * 60 { return true }
        return age >= 5 * 60 && !signers.isSubset(of: self.signers)
    }
}

struct YearReviewZapProvider: Codable, Sendable {
    let pubkey: String
    let keys: Set<String>
    let lud16: String?
    let lud06: String?

    static func from(events: [YearReviewEvent], authors: Set<String>) async -> [Self] {
        let task = Task.detached(priority: .utility) {
            var newest: [String: YearReviewEvent] = [:]
            for event in events where event.kind == 0 && authors.contains(event.pubkey) {
                guard !Task.isCancelled, let data = try? JSONEncoder().encode(event),
                      let signed = try? JSONDecoder().decode(NEvent.self, from: data), (try? signed.verified()) == true else { continue }
                if let old = newest[event.pubkey], old.createdAt > event.createdAt || old.createdAt == event.createdAt && old.id < event.id { continue }
                newest[event.pubkey] = event
            }
            return newest.values.compactMap { event -> Self? in
                guard let metadata = try? JSONDecoder().decode(NSetMetadata.self, from: Data(event.content.utf8)) else { return nil }
                return Self(pubkey: event.pubkey, keys: [], lud16: metadata.lud16, lud06: metadata.lud06)
            }
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    var endpoint: URL? {
        if let lud16, !lud16.isEmpty {
            let parts = lud16.split(separator: "@", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            var components = URLComponents()
            components.scheme = "https"; components.host = String(parts[1])
            components.path = "/.well-known/lnurlp/" + parts[0]
            return components.url
        }
        return lud06.flatMap { try? Bech32.decode(lnurl: $0) }
    }

    func resolve() async -> Set<String> {
        guard let endpoint, endpoint.scheme == "https", endpoint.host != nil else { return keys }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 64_000,
                  let info = try? JSONDecoder().decode(LUD16response.self, from: data), info.allowsNostr == true,
                  let key = info.nostrPubkey, YearReviewEvent.isHex(key, length: 64) else { return keys }
            return keys.union([key])
        } catch { return keys }
    }
}
