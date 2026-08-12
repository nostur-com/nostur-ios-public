//
//  SearchNavigationModel.swift
//  Nostur
//

import Combine
import Foundation

struct SearchNavigationRequest: Equatable, Identifiable {
    let id: UUID
    let query: String

    init(id: UUID = UUID(), query: String) {
        self.id = id
        self.query = query
    }
}

/// Retains searches that originate outside the Search tab until the primary
/// Search view is mounted and has applied them.
final class SearchNavigationModel: ObservableObject {
    static let shared = SearchNavigationModel()

    @Published private(set) var pendingRequest: SearchNavigationRequest?

    init() {}

    func openSearch(_ query: String) {
        setSelectedTab("Search")
        pendingRequest = SearchNavigationRequest(query: query)
    }

    func acknowledge(_ request: SearchNavigationRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}
