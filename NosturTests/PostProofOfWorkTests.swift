import XCTest
import NostrEssentials
@testable import Nostur

final class PostProofOfWorkTests: XCTestCase {
    func testCalibratedTargetRespectsTimeBudgetAndRoundsDownToWholeBits() {
        XCTAssertEqual(PostProofOfWork.defaultSeconds, 0.25)
        XCTAssertEqual(PostProofOfWork.clampedSeconds(0.1), 0.25)
        XCTAssertEqual(PostProofOfWork.target(for: 0.25, hashRate: 900_000), 17)
        XCTAssertEqual(PostProofOfWork.target(for: 0.5, hashRate: 900_000), 18)
        XCTAssertEqual(PostProofOfWork.target(for: 1, hashRate: 900_000), 19)
        XCTAssertEqual(PostProofOfWork.target(for: 2, hashRate: 900_000), 20)
        XCTAssertEqual(PostProofOfWork.target(for: 2.5, hashRate: 900_000), 21)
        XCTAssertEqual(PostProofOfWork.clampedSeconds(5), 2.5)
        XCTAssertEqual(PostProofOfWork.target(for: 5, hashRate: 900_000), 21)
        XCTAssertNil(PostProofOfWork.target(for: 0, hashRate: 900_000))
        XCTAssertNil(PostProofOfWork.target(for: 4, hashRate: 0))
    }

    func testSliderPreservesPreviouslyEnabledAndDisabledSettings() throws {
        let suite = "proof-of-work-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(PostProofOfWork.savedSeconds(in: defaults), 0)
        defaults.set(1.5, forKey: "post_proof_of_work_seconds")
        XCTAssertEqual(PostProofOfWork.savedSeconds(in: defaults), 0)
        defaults.set(true, forKey: "post_proof_of_work_enabled")
        XCTAssertEqual(PostProofOfWork.savedSeconds(in: defaults), 1.5)
        defaults.set(0.0, forKey: PostProofOfWork.secondsKey)
        XCTAssertEqual(PostProofOfWork.savedSeconds(in: defaults), 0)
    }

    func testTimeoutOddsUseTheActualTargetAndMeasuredRate() {
        let hashRate = pow(2, 20.0) / 2.5
        let oddsAtMaximum = PostProofOfWork.postsPerTimeout(target: 20, hashRate: hashRate)
        let oddsAtLowerTarget = PostProofOfWork.postsPerTimeout(target: 19, hashRate: hashRate)
        XCTAssertEqual(oddsAtMaximum, 22_027, accuracy: 2)
        XCTAssertGreaterThan(oddsAtLowerTarget, oddsAtMaximum)
    }

    func testBenchmarkReturnsAUsableRate() async throws {
        let rate = try await PostProofOfWork.benchmark()
        XCTAssertGreaterThan(rate, 0)
        XCTAssertNotNil(PostProofOfWork.target(for: 1, hashRate: rate))
    }

    func testMiningPreservesChatReactionVoteAndRepostPayloads() async throws {
        let author = String(repeating: "1", count: 64)
        let referencedID = String(repeating: "2", count: 64)
        let cases: [(NEventKind, String, [[String]])] = [
            (.chatMessage, "Hello", [["a", "30311:\(author):stream"], ["e", referencedID]]),
            (.reaction, "🔥", [["e", referencedID], ["p", author]]),
            (.pollResponse, "", [["e", referencedID], ["response", "choice"]]),
            (.repost, "{\"id\":\"\(referencedID)\"}", [["e", referencedID], ["p", author]])
        ]
        for (kind, content, tags) in cases {
            let unsigned = NEvent(publicKey: author, content: content, kind: kind, tags: tags.map(NostrTag.init))
            let mined = try await PostProofOfWork.mine(unsigned, target: 6)
            XCTAssertEqual(mined.kind, kind)
            XCTAssertEqual(mined.content, content)
            XCTAssertEqual(mined.tags.dropLast().map(\.tag), tags)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(PostProofOfWork.difficulty(of: mined)), 6)
        }
    }

    func testWispPostHas18BitsOfProofOfWork() throws {
        let json = #"""
        {"content":"Stop paying top dollar for the latest frontier model when you can get the same results with a cheaper open model. You wouldn’t hire a Rocket Scientist to do your work, would you?\n\nSay goodbye to artificial hourly and weekly limits that only slow you down.\n\nUsing open models doesn’t equate to running them locally, so don’t confuse the two.","tags":[["client","Wisp iOS"],["nonce","46644","18"]],"pubkey":"00000000827ffaa94bfea288c3dfce4422c794fbb96625b6b31e9049f729d700","id":"00003377109d55828a9f34faf5d88669c91d836cd9bb18004dde8e4f0566fb8c","kind":1,"created_at":1795534872,"sig":"7736873b81ad34393a5e6182111bbadc37dad8876a22ba9f5b0e32c6333153fb8a4efd74f3b318695fc3ffff6389ddc03dd19c0b45033bb84a45d92f0ac6c62d"}
        """#
        var event = try JSONDecoder().decode(NEvent.self, from: Data(json.utf8))
        XCTAssertEqual(PostProofOfWork.difficulty(of: event), 18)
        event.content += " Edited."
        XCTAssertNil(PostProofOfWork.difficulty(of: event))
    }

    func testAmethystPostHas24BitsWithAnAlphanumericNonce() throws {
        let json = #"""
        {"sig":"9817520a2c8983b5aff1c93744f6543385ea92f55ebffec87ffdf778e2b0ba376400da14e694d9b8cc1d2ae270125f3a4e05b93a591d1fc29d70d3f793f503b2","content":"Posting from Amethyst iOS with pow","id":"00000098d8bdb5531c7b1426d80838916584acc218943da9cf8a66f371852514","created_at":1795628034,"tags":[["client","Amethyst"],["nonce","001zUi","24"]],"pubkey":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c","kind":1}
        """#
        var event = try JSONDecoder().decode(NEvent.self, from: Data(json.utf8))
        XCTAssertEqual(PostProofOfWork.difficulty(of: event), 24)

        event.tags[1] = NostrTag(["nonce", "001zUj", "24"])
        XCTAssertNil(PostProofOfWork.difficulty(of: event))
    }

    func testReportsActualDifficultyWithoutATarget() throws {
        let json = #"""
        {"id":"000006d8c378af1779d2feebc7603a125d99eca0ccf1085959b307f64e5dd358","pubkey":"a48380f4cfcc1ad5378294fcac36439770f9c878dd880ffa94bb74ea54a6f243","created_at":1651794653,"kind":1,"tags":[["nonce","776797","20"]],"content":"It's just me mining my own business"}
        """#
        var event = try JSONDecoder().decode(NEvent.self, from: Data(json.utf8))
        XCTAssertEqual(PostProofOfWork.difficulty(of: event), 21)

        // The target is optional. Find a cheap fixture where a nonce without a target still has work.
        event.tags = [NostrTag(["nonce", "2"])]
        event = event.withId()
        XCTAssertEqual(PostProofOfWork.difficulty(of: event), 1)
    }

    func testClaimed18BitsCannotMakeMissingWorkAppear() {
        var event = NEvent(publicKey: "a48380f4cfcc1ad5378294fcac36439770f9c878dd880ffa94bb74ea54a6f243",
                           createdAt: NTimestamp(timestamp: Int(123)), content: "Test", kind: .textNote,
                           tags: [NostrTag(["nonce", "0", "18"])])
        event = event.withId()
        XCTAssertNil(PostProofOfWork.difficulty(of: event))

        event.tags = [NostrTag(["nonce", "1", "18"])]
        event = event.withId()
        XCTAssertEqual(PostProofOfWork.difficulty(of: event), 2)
    }

    func testMiningPreservesTheEventThatGetsSigned() async throws {
        let keys = try Keys(privateKeyHex: String(repeating: "1", count: 64))
        let event = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: Int(123)),
                           content: "A \"quote\", a line break\n, and https://example.com/🌱", kind: .textNote,
                           tags: [NostrTag(["nonce", "3", "1"]), NostrTag(["t", "garden"])])
        var mined = try await PostProofOfWork.mine(event, target: 18)

        XCTAssertEqual(mined.publicKey, event.publicKey)
        XCTAssertEqual(mined.createdAt.timestamp, event.createdAt.timestamp)
        XCTAssertEqual(mined.kind, event.kind)
        XCTAssertEqual(mined.content, event.content)
        XCTAssertEqual(mined.tags.count, 2)
        XCTAssertEqual(mined.tags.first?.tag, ["t", "garden"])
        XCTAssertEqual(mined.tags.last?.tag.last, "18")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(PostProofOfWork.difficulty(of: mined)), 18)
        let minedID = mined.id
        XCTAssertEqual(mined.withId().id, minedID)
        let signed = try mined.sign(keys)
        XCTAssertEqual(signed.id, minedID)
        XCTAssertTrue(try signed.verified())
    }

    func testMiningHonorsCancellation() async {
        let job = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PostProofOfWork.mine(NEvent(content: "Cancelled"), target: 18)
        }
        do {
            _ = try await job.value
            XCTFail("A cancelled task returned a mined event")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
