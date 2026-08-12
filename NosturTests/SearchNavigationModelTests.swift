//
//  SearchNavigationModelTests.swift
//  NosturTests
//

import Combine
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

    func testSelectsSearchTabBeforePublishingRequest() {
        let model = SearchNavigationModel()
        var cancellable: AnyCancellable?
        var selectedTabWhenPublished: String?

        cancellable = model.$pendingRequest
            .compactMap { $0 }
            .sink { _ in
                selectedTabWhenPublished = selectedTab()
            }

        model.openSearch("#nostr")

        XCTAssertEqual(selectedTabWhenPublished, "Search")
        withExtendedLifetime(cancellable) {}
    }
}
