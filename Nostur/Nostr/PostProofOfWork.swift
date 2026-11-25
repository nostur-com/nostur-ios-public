import CryptoKit
import Foundation
import NostrEssentials

enum PostProofOfWork {
    static let enabledKey = "post_proof_of_work_enabled"
    static let secondsKey = "post_proof_of_work_seconds"
    static let hashRateKey = "post_proof_of_work_hash_rate"
    static let timeRange = 0.25...2.5
    static let defaultSeconds = 0.25

    static func clampedSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultSeconds }
        return min(timeRange.upperBound, max(timeRange.lowerBound, seconds))
    }

    static var configuredTarget: Int? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let seconds = defaults.object(forKey: secondsKey) as? Double ?? defaultSeconds
        return target(for: seconds, hashRate: defaults.double(forKey: hashRateKey))
    }

    static func target(for seconds: Double, hashRate: Double) -> Int? {
        guard hashRate.isFinite, hashRate > 0 else { return nil }
        let bits = log2(hashRate) + log2(clampedSeconds(seconds))
        return Int(min(30, max(1, bits.rounded(.down))))
    }

    private enum MiningError: Error {
        case invalidEvent
        case timedOut
    }

    static func difficulty(of event: NEvent) -> Int? {
        guard !event.id.isEmpty, event.tags.contains(where: { tag in
            tag.type == "nonce" && !tag.value.isEmpty && tag.value.utf8.allSatisfy { (48...57).contains($0) }
        }), let serialized = try? event.serializedForID() else { return nil }

        let digest = CryptoKit.SHA256.hash(data: serialized)
        let bits = leadingZeroBits(in: digest)
        guard bits > 0, String(bytes: digest.bytes) == event.id else { return nil }
        return bits
    }

    static func mine(_ unsignedEvent: NEvent, target: Int) async throws -> NEvent {
        let worker = Task.detached(priority: .userInitiated) {
            try search(unsignedEvent, target: target)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func benchmark() async throws -> Double {
        let worker = Task.detached(priority: .userInitiated) {
            let sample = NEvent(publicKey: String(repeating: "0", count: 64),
                                content: String(repeating: "A short sample post. ", count: 12), kind: .textNote)
            let template = try MiningTemplate(event: sample, target: 20)
            let start = ProcessInfo.processInfo.systemUptime
            var attempts = 0
            var totalLeadingBits = 0
            var elapsed: TimeInterval
            repeat {
                try Task.checkCancellation()
                for nonce in attempts..<(attempts + 1024) {
                    totalLeadingBits += template.difficulty(nonce: String(nonce)).bits
                }
                attempts += 1024
                elapsed = ProcessInfo.processInfo.systemUptime - start
            } while elapsed < 0.15
            guard totalLeadingBits > 0 else { throw MiningError.invalidEvent }
            return Double(attempts) / elapsed
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func search(_ unsignedEvent: NEvent, target: Int) throws -> NEvent {
        try Task.checkCancellation()
        guard (1...256).contains(target) else { throw MiningError.invalidEvent }
        var event = unsignedEvent
        event.id = ""
        event.signature = ""
        event.tags.removeAll { $0.type == "nonce" }

        let targetText = String(target)
        event.tags.append(NostrTag(["nonce", "0", targetText]))
        let template = try MiningTemplate(taggedEvent: event, target: target)

        let deadline = ProcessInfo.processInfo.systemUptime + 25
        var nonce: UInt64 = 0
        while true {
            if nonce.isMultiple(of: 1024) {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw MiningError.timedOut }
            }

            let nonceText = String(nonce)
            let result = template.difficulty(nonce: nonceText)
            if result.bits >= target {
                try Task.checkCancellation()
                event.tags[event.tags.count - 1] = NostrTag(["nonce", nonceText, targetText])
                event.id = String(bytes: result.digest.bytes)
                return event
            }
            nonce += 1
        }
    }

    private struct MiningTemplate {
        private let prefixHash: CryptoKit.SHA256
        private let suffix: Data

        init(event: NEvent, target: Int) throws {
            var event = event
            event.tags.append(NostrTag(["nonce", "0", String(target)]))
            try self.init(taggedEvent: event, target: target)
        }

        init(taggedEvent: NEvent, target: Int) throws {
            let serialized = try taggedEvent.serializedForID()
            // Only the decimal nonce varies between attempts.
            let tag = Data("[\"nonce\",\"0\",\"\(target)\"]".utf8)
            guard let tagRange = serialized.range(of: tag, options: .backwards) else { throw MiningError.invalidEvent }
            let nonceStart = tagRange.lowerBound + "[\"nonce\",\"".utf8.count
            suffix = serialized.suffix(from: nonceStart + 1)
            var hash = CryptoKit.SHA256()
            hash.update(data: serialized.prefix(upTo: nonceStart))
            prefixHash = hash
        }

        func difficulty(nonce: String) -> (bits: Int, digest: CryptoKit.SHA256.Digest) {
            var hash = prefixHash
            hash.update(data: Data(nonce.utf8))
            hash.update(data: suffix)
            let digest = hash.finalize()
            return (leadingZeroBits(in: digest), digest)
        }
    }

    private static func leadingZeroBits(in digest: CryptoKit.SHA256.Digest) -> Int {
        var bits = 0
        for byte in digest {
            bits += byte.leadingZeroBitCount
            if byte != 0 { break }
        }
        return bits
    }
}
