//
//  Deduplicator.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/10/2024.
//

import Foundation
import CoreData
import Combine

final class NXCloudSeenRefreshScheduler {
    private var task: Task<Void, Never>?

    @MainActor
    func schedule(
        debounceNanoseconds: UInt64 = 500_000_000,
        load: @escaping @MainActor () async -> Set<String>,
        apply: @escaping @MainActor (Set<String>) -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }

            let seenIds = await load()
            guard !Task.isCancelled else { return }

            self?.task = nil
            apply(seenIds)
        }
    }
}

class Deduplicator {
    // prefix / .shortId only
    public var onScreenSeen: Set<String> {
        get { _onScreenSeen }
        set { replaceOnScreenSeen(newValue) }
    }
    public var cloudSyncedSeen: Set<String> { cloudSeen }
    public let onScreenSeenInsertedSubject = PassthroughSubject<Set<String>, Never>()
    /// IDs learned from the CloudKit-backed read state. Columns treat these as
    /// authoritative after waiting for their viewport to become idle.
    public let cloudSeenInsertedSubject = PassthroughSubject<Set<String>, Never>()
    static let shared = Deduplicator()
    
    private var _onScreenSeen: Set<String> = []
    private var cloudSeen: Set<String> = []
    private var pendingOnScreenSeenInserted: Set<String> = []
    private var pendingOnScreenSeenInsertedFlush: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private let cloudSeenRefreshScheduler = NXCloudSeenRefreshScheduler()
    
    private init() {
        if SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud {
            self.preloadLastReadFromCloudFeeds()
        }

        DataProvider.shared().cloudStoreRemoteChangeSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleCloudSeenRefresh()
                }
            }
            .store(in: &subscriptions)
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

    @MainActor
    private func scheduleCloudSeenRefresh() {
        guard SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud else { return }

        cloudSeenRefreshScheduler.schedule(
            load: {
                let context = DataProvider.shared().container.newBackgroundContext()
                context.name = "cloud-seen-refresh"
                context.undoManager = nil
                return await Self.fetchCloudSeenIds(context: context)
            },
            apply: { [weak self] seenIds in
                self?.mergeCloudSeenIds(seenIds)
            }
        )
    }

    @MainActor
    private func mergeCloudSeenIds(_ seenIds: Set<String>) {
        // Compare with the last cloud snapshot, not the local seen set. An ID may
        // already be locally visible in another column; its later CloudKit arrival
        // still makes it authoritative for removing restored unread rows.
        let insertedIds = seenIds.subtracting(cloudSeen)
        guard !insertedIds.isEmpty else { return }

        cloudSeen.formUnion(insertedIds)
        _onScreenSeen.formUnion(insertedIds)
        cloudSeenInsertedSubject.send(insertedIds)
#if DEBUG
        L.og.debug("Merged \(insertedIds.count) remotely synced seen IDs -[LOG]-")
#endif
    }

    private static func fetchCloudSeenIds(context: NSManagedObjectContext) async -> Set<String> {
        return await context.perform {
            let request = NSFetchRequest<NSDictionary>(entityName: "CloudFeed")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["lastRead_"]
            request.includesPendingChanges = false

            do {
                let rows = try context.fetch(request)
                return Set(
                    rows.compactMap { $0["lastRead_"] as? String }
                        .flatMap { $0.split(separator: " ").map(String.init) }
                )
            }
            catch {
                L.og.error("Could not refresh remotely synced seen IDs: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    private func preloadLastReadFromCloudFeeds() {
        // Fetch all pinned CloudFeed, union all .lastRead, store in onScreenSeen
        let feeds = CloudFeed.fetchAll(context: viewContext())
        let seenIds = Set(feeds.flatMap { $0.lastRead })
        cloudSeen = seenIds
        self.onScreenSeen = seenIds
#if DEBUG
        L.og.debug("Preloaded onScreenSeen with \(self.onScreenSeen.count) entries -[LOG]-")
#endif
    }
}
