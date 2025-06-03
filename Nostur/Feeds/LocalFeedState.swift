//
//  LocalFeedState.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2025.
//

import Foundation
import Combine

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
    public var scrollToId: String? // restore scroll to this post (if there were unread items on save)
    
    public init(cloudFeedId: String, onScreenIds: [String], parentIds: Set<String>, scrollToId: String? = nil) {
        self.cloudFeedId = cloudFeedId
        self.onScreenIds = onScreenIds
        self.parentIds = parentIds
        self.scrollToId = scrollToId
    }
}

// MARK: - Storage
public final class LocalFeedStateManager {
    
 
    public static let shared = LocalFeedStateManager()
    
    private let userDefaultsKey = "localFeedStates"
    
    @MainActor
    private var _states: LocalFeedStates?
    
    private var saveToDiskSub: AnyCancellable?
    
    private init() {
        loadFromDisk()
        saveToDiskSub = FeedsCoordinator.shared.pauseFeedsSubject
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] in
                Task { @MainActor in
                    self?.saveToDisk()
                }
            }
    }
    
    // MARK: - Public Interface
    
    @MainActor
    public var states: LocalFeedStates? {
        _states
    }
    
    public func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let states = try? JSONDecoder().decode(LocalFeedStates.self, from: data) else {
            Task { @MainActor in
                _states = nil
            }
            return
        }
        Task { @MainActor in
            _states = states
        }
    }
    
    @MainActor
    public func saveToDisk() {
        guard let states = _states,
              let encoded = try? JSONEncoder().encode(states) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }
    
    @MainActor
    public func updateFeedState(_ feedState: LocalFeedState) {
        var currentStates = _states?.localFeedStates ?? []
        
        // Remove existing state for this feed if it exists
        currentStates.removeAll { $0.cloudFeedId == feedState.cloudFeedId }
        
        // Add the new state
        currentStates.append(feedState)
        
        // Update in-memory state
        _states = LocalFeedStates(localFeedStates: currentStates)
    }
    
    @MainActor
    public func feedState(for cloudFeedId: String) -> LocalFeedState? {
        _states?.feedState(for: cloudFeedId)
    }
}

// MARK: - Convenience Methods
extension LocalFeedStates {
    public func feedState(for cloudFeedId: String) -> LocalFeedState? {
        localFeedStates.first { $0.cloudFeedId == cloudFeedId }
    }
}
