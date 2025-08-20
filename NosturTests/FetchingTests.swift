//
//  FetchingTests.swift
//  NosturTests
//
//  Created by Fabian Lachman on 01/08/2025.
//

import Foundation
import Testing
@testable import Nostur
@testable import NostrEssentials
import SwiftUI

struct FetchingTests {
    
    let backlog = Backlog.shared

    @available(iOS 16.0, *)
    @Test func testFetchHighlights() async throws {
        
        let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        let accountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        
        // This local test relay should have some data or test will fail (TODO: setup proper mock test relay in tests)
        ConnectionPool.shared.addConnection(RelayData.new(url: "ws://localhost:4736", read: true, write: true, search: true, auth: false, excludedPubkeys: []))
        
        // Fetch from relays
        _ = try await relayReq(Filters(authors: [pubkey], kinds: [10001]), accountPubkey: accountPubkey)
        
        // Fetch from DB
        let postIds: [String] = await withBgContext { _ in
            Event.fetchReplacableEvent(10001, pubkey: pubkey)?.fastEs.map { $0.1 } ?? []
        }
        
        // Fetch from relays
        _ = try await relayReq(Filters(ids: Set(postIds)), accountPubkey: accountPubkey)
        
        
        // Fetch from DB
        let nrPosts: [NRPost] = await withBgContext { bg in
            Event.fetchEvents(postIds).map { NRPost(event: $0) }
        }
                
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 3.0))
        
        #expect(nrPosts.count > 0, "Should have some post")
    }
    
    @available(iOS 16.0, *)
    @Test func testFetchHighlightsTimeout() async throws {
        let pubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        let accountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        
        // This local test relay should have some data or test will fail (TODO: setup proper mock test relay in tests)
        ConnectionPool.shared.addConnection(RelayData.new(url: "ws://localhost:4736", read: true, write: true, search: true, auth: false, excludedPubkeys: []))
        
        Task {
            await #expect(throws: FetchError.timeout) {
                // Fetch from relays (should timeout)
                _ = try await relayReq(Filters(authors: [pubkey], kinds: [10001]), accountPubkey: accountPubkey)
            }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 6.0))
    }
}



//func loadUserAndSettings() async throws -> (User, Settings) {
//    async let user = fetcher.fetchUser()
//    async let settings = fetcher.fetchSettings()
//    return try await (user, settings)
//}


//func fetchIDs() async throws -> [Int] {
//    do {
//        return try await withTimeout(2) { try await fetcher.fetchIds() }
//    } catch is TimeoutError {
//        throw MyAppError.timeout
//    } catch {
//        throw MyAppError.fetchIdsFailed
//    }
//}
//
//func fetchPosts(ids: [Int]) async throws -> [Post] {
//    do {
//        return try await withTimeout(2) { try await fetcher.fetchPosts(ids) }
//    } catch is TimeoutError {
//        throw MyAppError.timeout
//    } catch {
//        throw MyAppError.fetchPostsFailed
//    }
//}
//
//
//func loadPostsFlow() async -> Result<[Post], MyAppError> {
//    do {
//        let ids = try await fetchIDs()
//        let posts = try await fetchPosts(ids: ids)
//        return .success(posts)
//    } catch let error as MyAppError {
//        return .failure(error)
//    } catch {
//        return .failure(.unknown(error))
//    }
//}

//
///// Run an async operation with an optional timeout.
//func withTimeout<T>(
//    _ seconds: Double,
//    operation: @escaping () async throws -> T
//) async throws -> T {
//    try await withThrowingTaskGroup(of: T.self) { group in
//        group.addTask {
//            try await operation()
//        }
//        group.addTask {
//            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
//            throw TimeoutError()
//        }
//        let result = try await group.next()!
//        group.cancelAll()
//        return result
//    }
//}
//
//struct TimeoutError: Error {}
