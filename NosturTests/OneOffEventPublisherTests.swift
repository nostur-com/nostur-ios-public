//
//  OneOffEventPublisherTests.swift
//  NosturTests
//
//  Created by Fabian Lachman on 30/08/2025.
//

import Foundation
import Testing
@testable import Nostur
@testable import NostrEssentials

struct OneOffEventPublisherTests {
    
    let testPk: String = "" // test private key
    let testEventJson = ###"{"kind":1,"id":"0179c49e5a2108f6efaaac48b80d8fd98e77d15ee956f7b77235014ae68d27bf","pubkey":"4b2fd609cf60e9769440bc3cb03d1f60eeac6d55f69938048dd401bef8d9a9c4","created_at":1756502929,"tags":[["-"]],"content":"test","sig":"d7cfa5cec0186f8ca1b4dd73a6dda7ffb4139f641c762c39818a3305ac7856cc621a97067ec8884e8e4fdf34de97b2ab94bf2ebbfa614b4598274d6fb54acae6"}"###
    let testNEvent: NEvent = Nostur.testNEvent(###"{"kind":1,"id":"0179c49e5a2108f6efaaac48b80d8fd98e77d15ee956f7b77235014ae68d27bf","pubkey":"4b2fd609cf60e9769440bc3cb03d1f60eeac6d55f69938048dd401bef8d9a9c4","created_at":1756502929,"tags":[["-"]],"content":"test","sig":"d7cfa5cec0186f8ca1b4dd73a6dda7ffb4139f641c762c39818a3305ac7856cc621a97067ec8884e8e4fdf34de97b2ab94bf2ebbfa614b4598274d6fb54acae6"}"###)

    @available(iOS 16.0, *)
    @Test func testSendEventToRelay() async throws {
        let connection = OneOffEventPublisher("ws://localhost:49201", signNEventHandler: { unsignedAuthResponse in
            L.og.debug("🔑 Signing auth response")
            return try localSignNEvent(unsignedAuthResponse, pk: testPk)
        })
        
        // 1. Connect to relay
        try await connection.connect()
        L.og.debug("✅ Connected to relay")
        
        // 2. Send event (this will automatically handle auth flow if needed)
        try await connection.publish(testNEvent, timeout: 5)
        L.og.debug("✅ Event sent successfully")
        
        // Test passes if we reach this point without throwing
        #expect(Bool(true))
    }

    
    @Test func testSendEventToOfflineRelay() async throws {
        let connection = OneOffEventPublisher("ws://localhost:11111", signNEventHandler: { unsignedAuthResponse in
            L.og.debug("🔑 Signing auth response")
            return try localSignNEvent(unsignedAuthResponse, pk: testPk)
        })
        
        // Expect connection to fail when connecting to offline relay
        await #expect(throws: NSError.self) {
            try await connection.connect()
        }
    }
    
}

