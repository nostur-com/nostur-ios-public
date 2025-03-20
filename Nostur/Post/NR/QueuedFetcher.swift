//
//  QueuedFetcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import Foundation
import Combine
import OrderedCollections

class QueuedFetcher {
    static let shared = QueuedFetcher()
    
    private var pQueue = Set<String>()
    private var idQueue = Set<String>()
    
    // TODO: finish recent cache - add recently tried queue, to not retry the same over and over..
    private var recentPs = OrderedSet<String>()
    private var recentIds = OrderedSet<String>()
    static let RECENT_LIMIT: Int = 300
    
    private var fetchSubscription: AnyCancellable?
    private var fetchSubject = PassthroughSubject<Void, Never>()
    private var ctx = bg()
    
    
    init() {
        setupDebouncedFetcher()
    }
    
    // call from bg context!
    public func addRecentP(pTag: String) {
        guard !recentPs.contains(pTag) else { return }
        recentPs.append(pTag)
        if recentPs.count > Self.RECENT_LIMIT {
            recentPs.removeFirst(100)
        }
    }
    
    // call from bg context!
    public func addRecentId(id: String) {
        guard !recentIds.contains(id) else { return }
        recentIds.append(id)
        if recentIds.count > Self.RECENT_LIMIT {
            recentIds.removeFirst(100)
        }
    }
    
    public func enqueue(pTag: String) {
        guard !recentPs.contains(pTag) else { return }
        ctx.perform { [weak self] in
            self?.pQueue.insert(pTag)
            self?.fetchSubject.send()
        }
    }
    
    public func enqueue(pTags: [String]) {
        guard !pTags.isEmpty else { return }
        ctx.perform { [weak self] in
            self?.pQueue.formUnion(pTags)
            self?.fetchSubject.send()
        }
    }
    
    public func enqueue(pTags: Set<String>) {
        guard !pTags.isEmpty else { return }
        ctx.perform { [weak self] in
            self?.pQueue.formUnion(pTags)
            self?.fetchSubject.send()
        }
    }
    
    public func dequeue(pTag: String) {
        ctx.perform { [weak self] in
            self?.pQueue.remove(pTag)
        }
    }
    
    public func dequeue(pTags: [String]) {
        guard !pTags.isEmpty else { return }
        ctx.perform { [weak self] in
            self?.pQueue.subtract(Set(pTags))
        }
    }
    
    public func dequeue(pTags: Set<String>) {
        guard !pTags.isEmpty else { return }
        ctx.perform { [weak self] in
            self?.pQueue.subtract(pTags)
        }
    }
    
    public func enqueue(id: String) {
        guard !recentIds.contains(id) else { return }
        ctx.perform { [weak self] in
            self?.idQueue.insert(id)
            self?.fetchSubject.send()
        }
    }
    
    public func enqueue(ids: [String]) {
        guard !ids.isEmpty else { return }
        ctx.perform { [weak self] in
            self?.idQueue.formUnion(Set(ids))
            self?.fetchSubject.send()
        }
    }
    
    public func dequeue(id: String) {
        ctx.perform { [weak self] in
            self?.idQueue.remove(id)
        }
    }
    
    public func dequeue(ids: [String]) {
        ctx.perform { [weak self] in
            self?.idQueue.subtract(Set(ids))
        }
    }
    
    private func setupDebouncedFetcher() {
        fetchSubscription = fetchSubject
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.ctx.perform { [weak self] in
                    guard let self else { return }
                    guard !self.pQueue.isEmpty || !self.idQueue.isEmpty else { return }
                    
                    if self.idQueue.isEmpty {
                        req(RM.getUserMetadata(pubkeys: Array(self.pQueue)))
                        self.pQueue.removeAll()
                    }
                    else if self.pQueue.isEmpty {
                        req(RM.getEvents(ids: Array(self.idQueue)))
                        self.idQueue.removeAll()
                    }
                    else {
                        // TODO COMBINE IN SINGLE REQUEST:
                        req(RM.getUserMetadata(pubkeys: Array(self.pQueue)))
                        req(RM.getEvents(ids: Array(self.idQueue)))
                        self.pQueue.removeAll()
                        self.idQueue.removeAll()
                    }
                }
            }
    }
    
}
