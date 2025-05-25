//
//  LocalFeedState.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2025.
//

import Foundation

public struct LocalFeedStates: Codable {
    public let localFeedStates: [LocalFeedState]
    
    public init(localFeedStates: [LocalFeedState]) {
        self.localFeedStates = localFeedStates
    }
}

public struct LocalFeedState: Codable {
    public let cloudFeedId: String // Cloud Core data field: CloudFeed.id (not ObjectID)
    public let onScreenIds: [String] // ids of posts on screen (order is relevant)
    public let parentIds: Set<String> // ids of parent posts (for reply-enabled feeds)
    
    public init(cloudFeedId: String, onScreenIds: [String], parentIds: Set<String>) {
        self.cloudFeedId = cloudFeedId
        self.onScreenIds = onScreenIds
        self.parentIds = parentIds
    }
}

// MARK: - Storage
extension LocalFeedStates {
    private static let userDefaultsKey = "localFeedStates"
    
    public static func save(_ states: LocalFeedStates) {
        if let encoded = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    public static func load() -> LocalFeedStates? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let states = try? JSONDecoder().decode(LocalFeedStates.self, from: data) else {
            return nil
        }
        return states
    }
}

// MARK: - Convenience Methods
extension LocalFeedStates {
    public func feedState(for cloudFeedId: String) -> LocalFeedState? {
        localFeedStates.first { $0.cloudFeedId == cloudFeedId }
    }
}
