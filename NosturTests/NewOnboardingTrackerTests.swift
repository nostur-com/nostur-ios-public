import CoreData
import XCTest
@testable import Nostur

@MainActor
final class NewOnboardingTrackerTests: XCTestCase {
    private final class Requests {
        private let lock = NSLock()
        private var stored: [String] = []
        func append(_ message: String) { lock.withLock { stored.append(message) } }
        var messages: [String] { lock.withLock { stored } }
    }

    private func pubkey() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func seedAccount(_ pubkey: String, withProfile: Bool) async throws {
        try await bg().perform {
            let account = CloudAccount(context: bg())
            account.publicKey = pubkey
            account.createdAt = .now
            if withProfile {
                let profile = NEvent(publicKey: pubkey, content: "{\"name\":\"Onboarding regression\"}", kind: .setMetadata)
                _ = Event.fromNEvent(nEvent: profile, context: bg())
            }
            try bg().save()
        }
    }

    private func removeAccount(_ pubkey: String, follows: Set<String>, tracker: NewOnboardingTracker) async throws {
        tracker.abort(pubkey: pubkey)
        try await bg().perform {
            if let account = try? CloudAccount.fetchAccount(publicKey: pubkey, context: bg()) { bg().delete(account) }
            let events = Event.fetchRequest()
            events.predicate = NSPredicate(format: "pubkey == %@", pubkey)
            try bg().fetch(events).forEach { bg().delete($0) }
            Contact.fetchByPubkeys(Array(follows), context: bg()).forEach { bg().delete($0) }
            try bg().save()
        }
    }

    private func importFollows(_ follows: Set<String>, pubkey: String, subscriptionID: String) async throws {
        try await bg().perform {
            let event = NEvent(publicKey: pubkey, content: "", kind: .contactList,
                               tags: follows.map { NostrTag(["p", $0]) })
            _ = Event.fromNEvent(nEvent: event, context: bg())
            try bg().save()
            Importer.shared.importedMessagesFromSubscriptionIds.send([subscriptionID])
        }
    }

    func testCachedProfileStillRequestsAndImportsFollows() async throws {
        let key = pubkey()
        let follows = Set((0..<870).map { _ in pubkey() })
        try await seedAccount(key, withProfile: true)
        let requests = Requests()
        let imported = expectation(description: "Follow-list import starts fetching followed profiles")
        let tracker = NewOnboardingTracker { message in
            requests.append(message)
            if message.contains("FPoF-") { imported.fulfill() }
        }
        try await tracker.start(pubkey: key)
        let request = try XCTUnwrap(requests.messages.first { $0.contains("FPF-") })
        let parts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.utf8)) as? [Any])
        let subscriptionID = try XCTUnwrap(parts[1] as? String)
        let filters = parts.dropFirst(2).compactMap { $0 as? [String: Any] }
        XCTAssertTrue(filters.contains { ($0["kinds"] as? [Int]) == [3] })
        try await importFollows(follows, pubkey: key, subscriptionID: subscriptionID)
        await fulfillment(of: [imported], timeout: 2)
        let storedFollows = await bg().perform {
            (try? CloudAccount.fetchAccount(publicKey: key, context: bg()))?.followingPubkeys
        }
        XCTAssertEqual(storedFollows, follows)
        try await removeAccount(key, follows: follows, tracker: tracker)
    }

    func testDelayedGuestPrefetchCannotReplaceRealLogin() async throws {
        let key = pubkey()
        let follows: Set<String> = [pubkey()]
        try await seedAccount(key, withProfile: false)
        let requests = Requests()
        let imported = expectation(description: "Real login still receives its follow list")
        let tracker = NewOnboardingTracker { message in
            requests.append(message)
            if message.contains("FPoF-") { imported.fulfill() }
        }
        try await tracker.start(pubkey: key)
        let request = try XCTUnwrap(requests.messages.first { $0.contains("FPF-") })
        let parts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.utf8)) as? [Any])
        let subscriptionID = try XCTUnwrap(parts[1] as? String)
        try await tracker.start(pubkey: GUEST_ACCOUNT_PUBKEY)
        tracker.abort(pubkey: GUEST_ACCOUNT_PUBKEY)
        XCTAssertFalse(requests.messages.contains { $0.contains(GUEST_ACCOUNT_PUBKEY) })
        try await importFollows(follows, pubkey: key, subscriptionID: subscriptionID)
        await fulfillment(of: [imported], timeout: 2)
        let storedFollows = await bg().perform {
            (try? CloudAccount.fetchAccount(publicKey: key, context: bg()))?.followingPubkeys
        }
        XCTAssertEqual(storedFollows, follows)
        try await removeAccount(key, follows: follows, tracker: tracker)
    }

    func testFollowListArrivingAfterFirstProfileResponseIsStillImported() async throws {
        let key = pubkey()
        let follows: Set<String> = [pubkey()]
        try await seedAccount(key, withProfile: false)
        let requests = Requests()
        let imported = expectation(description: "Late follow list is processed after profile response")
        let tracker = NewOnboardingTracker { message in
            requests.append(message)
            if message.contains("FPoF-") { imported.fulfill() }
        }
        try await tracker.start(pubkey: key)
        let request = try XCTUnwrap(requests.messages.first { $0.contains("FPF-") })
        let parts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.utf8)) as? [Any])
        let subscriptionID = try XCTUnwrap(parts[1] as? String)
        try await bg().perform {
            let profile = NEvent(publicKey: key, content: "{\"name\":\"Profile arrived first\"}", kind: .setMetadata)
            _ = Event.fromNEvent(nEvent: profile, context: bg())
            try bg().save()
            Importer.shared.importedMessagesFromSubscriptionIds.send([subscriptionID])
        }
        // Let ReqTask consume its first debounced response before kind 3 arrives.
        try await Task.sleep(nanoseconds: 250_000_000)
        try await importFollows(follows, pubkey: key, subscriptionID: subscriptionID)
        await fulfillment(of: [imported], timeout: 2)
        let storedFollows = await bg().perform {
            (try? CloudAccount.fetchAccount(publicKey: key, context: bg()))?.followingPubkeys
        }
        XCTAssertEqual(storedFollows, follows)
        try await removeAccount(key, follows: follows, tracker: tracker)
    }

    func testStartingLoginDoesNotBlockMainActorWhileImporterIsHeld() async throws {
        let key = pubkey()
        try await seedAccount(key, withProfile: true)
        let tracker = NewOnboardingTracker(sendRequest: { _ in })
        let releaseImport = DispatchSemaphore(value: 0)
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            bg().perform {
                started.resume()
                _ = releaseImport.wait(timeout: .now() + 3)
            }
        }
        defer { releaseImport.signal() }
        let start = Task { @MainActor in try await tracker.start(pubkey: key) }
        let responsive = expectation(description: "UI work runs while onboarding awaits importer")
        Task { @MainActor in responsive.fulfill() }
        await fulfillment(of: [responsive], timeout: 0.5)
        releaseImport.signal()
        try await start.value
        try await removeAccount(key, follows: [], tracker: tracker)
    }
}
