//
//  DataStore.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import Foundation
import Combine

class DataStore: ObservableObject {
    
    public static var shared = DataStore()
    var markAsRead = PassthroughSubject<Event?, Never>()
    var notesChanged = PassthroughSubject<[Event], Never>()
    
    @Published var unreadCount = 0
    
    var subscriptions = Set<AnyCancellable>()
    
    var mostRecentReadEvent:Event?
    
    var lastFiveEvents:[Event] = []
    
    init() {
        addSubscriptions()
    }
    
    func addSubscriptions() {
        markAsRead
            .removeDuplicates()
            .debounce(for: .seconds(0.05), scheduler: RunLoop.current)
            .compactMap { $0 }
            .filter { $0.created_at > (self.mostRecentReadEvent?.created_at ?? 0) }
            .sink(receiveValue: { event in
                if self.mostRecentReadEvent == nil || event.created_at > self.mostRecentReadEvent!.created_at {
                    self.mostRecentReadEvent = event
                    print("🟣🟣🟣 markAsRead: \(d(event.created_at).description)")
                }
            })
            .store(in: &subscriptions)
        
        markAsRead
            .removeDuplicates()
            .compactMap { $0 }
            .sink { event in
                self.lastFiveEvents.append(event)
                if (self.lastFiveEvents.count > 6) {
                    _ = self.lastFiveEvents.removeFirst()
                }
            }
            .store(in: &subscriptions)
        
        markAsRead
            .removeDuplicates()
            .compactMap { $0 }
            .debounce(for: .seconds(0.1), scheduler: RunLoop.current)
            .sink { _ in
                print("🟠🟠 fetching for ids: \(ids(self.lastFiveEvents))")
                sendNotification(.requestForJustAppeared, self.lastFiveEvents)
            }
            .store(in: &subscriptions)
        
        notesChanged
            .combineLatest(markAsRead)
            .debounce(for: .seconds(0.05), scheduler: RunLoop.current)
            .map({ (notes, mostRecentReadEvent) in
                return (notes.filter { $0.created_at > (self.mostRecentReadEvent?.created_at ?? 0) })
            })
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink(receiveValue: { unreadNotes in
                print("🟣🟣🟣 (notesChanged) unreadNotes.count: \(unreadNotes.count)")
                self.objectWillChange.send()
                self.unreadCount = unreadNotes.count
            })
            .store(in: &subscriptions)
            
    }
}
