//
//  Deduplicator.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/10/2024.
//

import Foundation
import CoreData

class Deduplicator {
    // prefix / .shortId only
    public var onScreenSeen: Set<String> = []
    static let shared = Deduplicator()
    
    private init() {
        if SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud {
            self.preloadLastReadFromCloudFeeds()
        }
    }
    
    private func preloadLastReadFromCloudFeeds() {
        // Fetch all pinned CloudFeed, union all .lastRead, store in onScreenSeen
        let feeds = CloudFeed.fetchAll(context: viewContext())
        let seenIds = feeds.flatMap { $0.lastRead } 
        self.onScreenSeen = Set(seenIds)
#if DEBUG
        L.og.debug("Preloaded onScreenSeen with \(self.onScreenSeen.count) entries -[LOG]-")
#endif
    }
}

