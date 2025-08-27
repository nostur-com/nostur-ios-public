//
//  ProfileHighlightsTests.swift
//  NosturTests
//
//  Created by Fabian Lachman on 27/08/2025.
//

import Foundation
import Testing
@testable import Nostur
@testable import NostrEssentials
import SwiftUI

struct ProfileHighlightsTests {
    
    let testPk: String = "" // test private key
    
    let backlog = Backlog.shared
    let up = Unpublisher.shared
    
    @available(iOS 16.0, *)
    @Test func testPinAPost() async throws {
        let keys = try Keys(privateKeyHex: testPk)

        let postToPin: NEvent? = NEvent.fromString(###"{"content":"https://media.utxo.nl/wp-content/uploads/nostr/c/0/c077b7aa917ade40e15d1cf9e98a1305e5a8c1a0d7c262f0d6ed508d42fc3ec4.webp\nTest 2","created_at":1755859838,"id":"eb84a53790fc1e911791af7fa97cba263b9970f695827a5cd6c39e29bbae3f6c","kind":1,"pubkey":"4b2fd609cf60e9769440bc3cb03d1f60eeac6d55f69938048dd401bef8d9a9c4","sig":"21ded06cb2c48cc065b57a4569e14df64a394ddd9b83bb0a42138cef22579f6a7b7d34622a22f22ae51535f5545d3108de3f5b1c0cae9a2c6e1536cc6379ae52","tags":[["imeta","url https://media.utxo.nl/wp-content/uploads/nostr/c/0/c077b7aa917ade40e15d1cf9e98a1305e5a8c1a0d7c262f0d6ed508d42fc3ec4.webp","dim 338x352","sha256 c077b7aa917ade40e15d1cf9e98a1305e5a8c1a0d7c262f0d6ed508d42fc3ec4"],["k","20"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]]}"###)
        
        #expect(postToPin != nil, "Failed to parse test post")
        guard let postToPin else { return }
        
        
        var latestPinned = NEvent(content: postToPin.eventJson(), kind: .latestPinned, tags: [
            NostrTag(["e", postToPin.id]),
            NostrTag(["k", postToPin.kind.id.description])
        ])
        
        let signedLatestPinned = try latestPinned.sign(keys)
        
        // Fetch highlights (kind 10001)
        let pubkey = keys.publicKeyHex
        let accountPubkey = keys.publicKeyHex
        
        // This local test relay should have some data or test will fail (TODO: setup proper mock test relay in tests)
        ConnectionPool.shared.addConnection(RelayData.new(url: "ws://192.168.11.110:10547", read: true, write: true, search: true, auth: false, excludedPubkeys: []))

        
        L.sockets.debug("Going to publish latest pinned")
        up.publishNow(signedLatestPinned)
        
        try await awaitWithRunLoop(timeout: 3) {
            _ = try? await relayReq(Filters(authors: [pubkey], kinds: [10001]), accountPubkey: accountPubkey)
        }
        
        // if we have have a hightlights list, add post to it, else create a new highlights list
        
        // Fetch from DB
        let highlightsListNEvent: Nostur.NEvent? = await withBgContext { _ in
            let highlightsListEvent: Nostur.Event? = Event.fetchReplacableEvent(10001, pubkey: pubkey)
            return highlightsListEvent?.toNEvent()
        }
        
        
        if let highlightsListNEvent { // Add (but no duplicates)
            if highlightsListNEvent.fastTags.first(where: { $0.1 == postToPin.id }) == nil {
                var updatedHighlightsListNEvent = highlightsListNEvent
                updatedHighlightsListNEvent.tags.append(NostrTag(["e", postToPin.id]))
                
                // sign
                let signed = try updatedHighlightsListNEvent.sign(keys)
                
                // publish and save
                L.sockets.debug("Going to publish updated highlights list")
                up.publishNow(signed)
            }
            else {
                L.sockets.debug("Highlights list already contains pinned post")
            }
        }
        else { // Create
            var newHighlightsList = NEvent(kind: .pinnedList,  tags: [NostrTag(["e", postToPin.id])])

            // sign
            let signed = try newHighlightsList.sign(keys)
            
            #expect(signed.fastTags.count == 1, "Signed event has wrong number of tags")
            
            // publish and save
            L.sockets.debug("Going to publish new highlights list")
            up.publishNow(signed)
        }
        
    }
    
    @available(iOS 16.0, *)
    @Test func testAddPostToHighlights() async throws {
        let keys = try Keys(privateKeyHex: testPk)

        // event id to add
        let eventIdToAdd = "cce2d1f961c551bc90d272f18407d51d113f99b9b47b08aa54ee08f716e53951"
        
        // Fetch highlights (kind 10001)
        let pubkey = keys.publicKeyHex
        let accountPubkey = keys.publicKeyHex
        
        // This local test relay should have some data or test will fail (TODO: setup proper mock test relay in tests)
        ConnectionPool.shared.addConnection(RelayData.new(url: "ws://192.168.11.110:10547", read: true, write: true, search: true, auth: false, excludedPubkeys: []))

        try await awaitWithRunLoop(timeout: 3) {
            _ = try? await relayReq(Filters(authors: [pubkey], kinds: [10001]), accountPubkey: accountPubkey)
        }
        
        // if we have have a hightlights list, add post to it, else create a new highlights list
        
        // Fetch from DB
        let highlightsListNEvent: Nostur.NEvent? = await withBgContext { _ in
            let highlightsListEvent: Nostur.Event? = Event.fetchReplacableEvent(10001, pubkey: pubkey)
            return highlightsListEvent?.toNEvent()
        }
        
        if let highlightsListNEvent { // Add (but no duplicates)
            if highlightsListNEvent.fastTags.first(where: { $0.1 == eventIdToAdd }) == nil {
                var updatedHighlightsListNEvent = highlightsListNEvent
                updatedHighlightsListNEvent.tags.append(NostrTag(["e", eventIdToAdd]))
                
                // sign
                let signed = try updatedHighlightsListNEvent.sign(keys)
                
                // publish and save
                up.publishNow(signed)
            }
        }
        else { // Create
            var newHighlightsList = NEvent(kind: .pinnedList,  tags: [NostrTag(["e", eventIdToAdd])])

            // sign
            let signed = try newHighlightsList.sign(keys)
            
            // publish and save
            up.publishNow(signed)
        }
        
    }
    
}
