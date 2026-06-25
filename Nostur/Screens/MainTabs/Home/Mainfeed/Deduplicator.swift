//
//  Deduplicator.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/10/2024.
//

import Foundation
import CoreData
import Combine

class Deduplicator {
    // prefix / .shortId only
    public var onScreenSeen: Set<String> {
        get { _onScreenSeen }
        set { replaceOnScreenSeen(newValue) }
    }
    public let onScreenSeenInsertedSubject = PassthroughSubject<Set<String>, Never>()
    static let shared = Deduplicator()
    
    private var _onScreenSeen: Set<String> = []
    private var pendingOnScreenSeenInserted: Set<String> = []
    private var pendingOnScreenSeenInsertedFlush: DispatchWorkItem?
    
    private init() {
        if SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud {
            self.preloadLastReadFromCloudFeeds()
        }
    }
    
    public func insertOnScreenSeen(_ shortId: String) {
        guard _onScreenSeen.insert(shortId).inserted else { return }
        enqueueOnScreenSeenInserted([shortId])
    }
    
    public func formUnionOnScreenSeen(_ shortIds: Set<String>) {
        var insertedIds = Set<String>()
        insertedIds.reserveCapacity(shortIds.count)
        
        for shortId in shortIds where _onScreenSeen.insert(shortId).inserted {
            insertedIds.insert(shortId)
        }
        
        enqueueOnScreenSeenInserted(insertedIds)
    }
    
    private func replaceOnScreenSeen(_ newValue: Set<String>) {
        let insertedIds = newValue.subtracting(_onScreenSeen)
        _onScreenSeen = newValue
        enqueueOnScreenSeenInserted(insertedIds)
    }
    
    private func enqueueOnScreenSeenInserted(_ insertedIds: Set<String>) {
        guard !insertedIds.isEmpty else { return }
        pendingOnScreenSeenInserted.formUnion(insertedIds)
        guard pendingOnScreenSeenInsertedFlush == nil else { return }
        
        let flush = DispatchWorkItem { [weak self] in
            self?.flushPendingOnScreenSeenInserted()
        }
        pendingOnScreenSeenInsertedFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: flush)
    }
    
    private func flushPendingOnScreenSeenInserted() {
        pendingOnScreenSeenInsertedFlush = nil
        let insertedIds = pendingOnScreenSeenInserted
        pendingOnScreenSeenInserted.removeAll(keepingCapacity: true)
        
        guard !insertedIds.isEmpty else { return }
        onScreenSeenInsertedSubject.send(insertedIds)
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
