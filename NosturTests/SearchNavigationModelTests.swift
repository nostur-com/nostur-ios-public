//
//  SearchNavigationModelTests.swift
//  NosturTests
//

import XCTest
@testable import Nostur

final class SearchNavigationModelTests: XCTestCase {
    func testRequestIsRetainedUntilAcknowledged() throws {
        let model = SearchNavigationModel()

        model.openSearch("#nostr")

        let request = try XCTUnwrap(model.pendingRequest)
        XCTAssertEqual(request.query, "#nostr")

        model.acknowledge(SearchNavigationRequest(query: "#other"))
        XCTAssertEqual(model.pendingRequest, request)

        model.acknowledge(request)
        XCTAssertNil(model.pendingRequest)
    }

    func testRepeatedQueryCreatesANewRequest() throws {
        let model = SearchNavigationModel()

        model.openSearch("#nostr")
        let firstRequest = try XCTUnwrap(model.pendingRequest)

        model.openSearch("#nostr")
        let secondRequest = try XCTUnwrap(model.pendingRequest)

        XCTAssertNotEqual(firstRequest.id, secondRequest.id)
    }
}
