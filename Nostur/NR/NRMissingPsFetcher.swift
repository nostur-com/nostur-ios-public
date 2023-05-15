//
//  NRMissingPsFetcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import Foundation
import Combine

class QueuedFetcher {
    static let shared = QueuedFetcher()
    
    var subscriptions = Set<AnyCancellable>()
    
    var pQueue = Set<String>()
    var idQueue = Set<String>()
    
    
    private var fetchSubject = PassthroughSubject<Void, Never>()
    private var enqueuePsubject = PassthroughSubject<String, Never>()
    private var dequeuePsubject = PassthroughSubject<String, Never>()
    private var enqueueIDsubject = PassthroughSubject<String, Never>()
    private var dequeueIDsubject = PassthroughSubject<String, Never>()
    
    init() {
        enqueuePsubject.sink { pTag in
            guard !self.pQueue.contains(pTag) else { return }
            self.pQueue.insert(pTag)
        }
        .store(in: &subscriptions)
        
        dequeuePsubject.sink { pTag in
            self.pQueue.remove(pTag)
        }
        .store(in: &subscriptions)
        
        enqueueIDsubject.sink { eventId in
            guard !self.idQueue.contains(eventId) else { return }
            self.idQueue.insert(eventId)
        }
        .store(in: &subscriptions)
        
        dequeueIDsubject.sink { eventId in
            self.idQueue.remove(eventId)
        }
        .store(in: &subscriptions)
        
        fetchSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { _ in
                guard self.pQueue.count > 0 || self.idQueue.count > 0 else { return }
                
                if self.idQueue.count == 0 {
                    req(RM.getUserMetadata(pubkeys: Array(self.pQueue)))
                    self.pQueue.removeAll()
                }
                else if self.pQueue.count == 0 {
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
        .store(in: &subscriptions)
    }
    
    public func enqueue(pTag: String) {
        enqueuePsubject.send(pTag)
        self.fetch()
    }
    
    public func enqueue(pTags: [String]) {
        pTags.forEach { pTag in
            enqueuePsubject.send(pTag)
        }
        self.fetch()
    }
    
    public func dequeue(pTag: String) {
        dequeuePsubject.send(pTag)
    }
    
    public func dequeue(pTags: [String]) {
        pTags.forEach { pTag in
            dequeuePsubject.send(pTag)
        }
    }
    
    
    public func enqueue(id: String) {
        enqueueIDsubject.send(id)
        self.fetch()
    }
    
    public func enqueue(ids: [String]) {
        ids.forEach { id in
            enqueuePsubject.send(id)
        }
        self.fetch()
    }
    
    public func dequeue(id: String) {
        dequeueIDsubject.send(id)
    }
    
    public func dequeue(ids: [String]) {
        ids.forEach { id in
            dequeueIDsubject.send(id)
        }
    }
    
    public func fetch() {
        fetchSubject.send()
    }
}
