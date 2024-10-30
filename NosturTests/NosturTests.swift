//
//  NosturTests.swift
//  NosturTests
//
//  Created by Fabian Lachman on 30/09/2024.
//

import XCTest
import Combine
@testable import Nostur


final class NosturTests: XCTestCase {
    
    let pl = NXPipelines.shared
    var subscriptions = Set<AnyCancellable>()

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        
//        pl.parsePipeline
//            .sink(
//                receiveCompletion: { _ in
//                    print("receiveCompletion")
//                },
//                receiveValue: { relayMessage in
//                    print(relayMessage.message)
//            })
//            .store(in: &subscriptions)
        
        pl.messageSubject.send(NXRelayMessage(
            message: ###"["EVENT","test",{"id":"ab9296f23a6324b5ef1c34cff32433838c58837d8bc6bc89875c970a6c1e6444","created_at":1726683588,"content":"nostr is censorship resistant because:\n\n1. the follow list is decentralized\n2. there are multiple relays\n\nNormal users can resist censorship by switching relays, or ultimately run their own relay and they cannot be censored on follow lists because each follower owns their own follow list, it doesn't even need to exist on a relay, can exists primarily on everyones own device while syncing to relays.\n\nRelays stopping spam doesn't mean nostr can be censored, it just means whatever was stopped was something no ones care about enough to either be followed or hosted on a different relay.\n","tags":[["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"kind":1,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","sig":"2047e9cb8d98629172bbd44d20b099943026e8bd7270c0a67339a789f399d8556c3497cb1e1efdecbf2266cb341d01434aedc0ba9d1419259fd6b062ce6898cf"}]"###,
            relay: "unit test"
        ))
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
