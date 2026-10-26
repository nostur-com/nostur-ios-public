import Combine
import CoreData
import XCTest
@testable import Nostur

@MainActor
final class LoginFeedStateTests: XCTestCase {
    private func account(in context: NSManagedObjectContext) -> CloudAccount {
        let entity = DataProvider.shared().container.managedObjectModel.entitiesByName["CloudAccount"]!
        let account = CloudAccount(entity: entity, insertInto: context)
        account.publicKey = String(repeating: "a", count: 64)
        return account
    }

    func testImportedFollowsRefreshBeforeBackgroundAccountIsReady() async {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let account = account(in: context)
        let releaseImport = DispatchSemaphore(value: 0)
        defer { releaseImport.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            bg().perform {
                started.resume()
                _ = releaseImport.wait(timeout: .now() + 5)
            }
        }

        let loggedInAccount = LoggedInAccount(account)
        XCTAssertEqual(loggedInAccount.viewFollowingPublicKeys, [account.publicKey])
        let follows = Set((1...870).map { String(format: "%064x", $0) })
        let privateFollow = String(repeating: "b", count: 64)
        account.followingPubkeys = follows
        account.privateFollowingPubkeys = [privateFollow]

        let start = Date()
        loggedInAccount.reloadFollows()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        let expected = follows.union([account.publicKey, privateFollow])
        XCTAssertEqual(loggedInAccount.viewFollowingPublicKeys, expected)
        XCTAssertEqual(loggedInAccount.followingPublicKeys, expected)

        // Simulate a Core Data merge bypassing the cached convenience setter.
        account.followingPubkeys_ = String(repeating: "c", count: 64)
        loggedInAccount.reloadFollows()
        XCTAssertEqual(loggedInAccount.viewFollowingPublicKeys,
                       [account.publicKey, privateFollow, String(repeating: "c", count: 64)])
    }

    func testExploreRestartsWhenItsContactListArrives() async throws {
        let previousPubkeys = AppState.shared.rawExplorePubkeys
        defer { AppState.shared.rawExplorePubkeys = previousPubkeys }
        AppState.shared.rawExplorePubkeys = []
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let entity = DataProvider.shared().container.managedObjectModel.entitiesByName["CloudFeed"]!
        let feed = CloudFeed(entity: entity, insertInto: context)
        feed.id = UUID()
        feed.accountPubkey = EXPLORER_PUBKEY
        let config = NXColumnConfig(id: "Explore-login-test", columnType: .following(feed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
        let vm = NXColumnViewModel()
        vm.isVisible = true
        vm.initialize(config, speedTest: NXSpeedTest())
        defer { vm.isVisible = false }
        vm.viewState = .timeout
        let restarted = expectation(description: "Explore restarted after contact list import")
        let subscription = vm.$viewState.dropFirst().sink { state in
            if case .loading = state { restarted.fulfill() }
        }
        AppState.shared.rawExplorePubkeys = [String(repeating: "d", count: 64)]
        await fulfillment(of: [restarted], timeout: 1.0)
        subscription.cancel()
    }

    func testExploreLeavesSpinnerWhenNoContactListArrives() async {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let entity = DataProvider.shared().container.managedObjectModel.entitiesByName["CloudFeed"]!
        let feed = CloudFeed(entity: entity, insertInto: context)
        let config = NXColumnConfig(id: "Explore-timeout-test", columnType: .following(feed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
        let vm = NXColumnViewModel()
        vm.config = config
        vm.viewState = .loading
        let finished = expectation(description: "Explore stops waiting for missing contact list")
        let subscription = vm.$viewState.dropFirst().sink { state in
            if case .timeout = state { finished.fulfill() }
        }
        vm.scheduleInitialFeedTimeout(for: config, timeoutNanoseconds: 1_000_000)
        await fulfillment(of: [finished], timeout: 1.0)
        subscription.cancel()
    }
}
