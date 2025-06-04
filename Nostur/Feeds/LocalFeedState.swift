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
    private var states: LocalFeedStates?
    private var saveToDiskSub: AnyCancellable?
    private var wipStatesSub: AnyCancellable?
    
    private init() {
        loadFromDisk()
        
        wipStatesSub = FeedsCoordinator.shared.saveFeedStatesSubject
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    self?.states = LocalFeedStates(localFeedStates: [])
#if DEBUG
                    L.og.debug("💾 Feed states: states wiped")
#endif
                }
            }
        
        saveToDiskSub = FeedsCoordinator.shared.saveFeedStatesSubject
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    self?.saveToDisk()
                }
            }
    }
    
    // MARK: - Public Interface

    public func getFeedStates() -> [LocalFeedState] {
        return states?.localFeedStates ?? []
    }

    public func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let states = try? JSONDecoder().decode(LocalFeedStates.self, from: data) else {
            Task { @MainActor in
                self.states = nil
            }
            return
        }
        Task { @MainActor in
            self.states = states
        }
    }
    
    @MainActor
    public func saveToDisk() {
        guard let states = self.states,
              let encoded = try? JSONEncoder().encode(states) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
#if DEBUG
        L.og.debug("💾 Feed states: saveToDisk() - feeds: \(states.localFeedStates.count)")
#endif
    }
    
    @MainActor
    public func updateFeedState(_ feedState: LocalFeedState) {
        var currentStates = states?.localFeedStates ?? []
        
        // Remove existing state for this feed if it exists
        currentStates.removeAll { $0.cloudFeedId == feedState.cloudFeedId }
        
        // Add the new state
        currentStates.append(feedState)
        
        // Update in-memory state
        states = LocalFeedStates(localFeedStates: currentStates)
    }
    
    @MainActor
    public func feedState(for cloudFeedId: String) -> LocalFeedState? {
        states?.feedState(for: cloudFeedId)
    }
    
    public func wipeMemory() {
        Task { @MainActor in
            states = LocalFeedStates(localFeedStates: [])
        }
    }
}

// MARK: - Convenience Methods
extension LocalFeedStates {
    public func feedState(for cloudFeedId: String) -> LocalFeedState? {
        localFeedStates.first { $0.cloudFeedId == cloudFeedId }
    }
}


// How are Feed states saved?


// 1. App goes to background (scenePhase) -> .saveFeedStates() -> saveFeedStatesSubject
// 2. After 0.1 sec debounce: Wipe old feed states (to only keep pinned tabs): LocalFeedStateManager.wipStatesSub
// 3. After 0.5 sec debounce: Save feed state for each NXColumnViewModel: listenForSaveFeedStates -> saveFeedState()
// 4. After 1.5 sec debounce: Save all feed states to NSUserDefaults (LocalFeedStateManager.saveToDiskSub)
