//
//  DataStore.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI
import Foundation
import Combine

class DataStore: ObservableObject {
    
    public static var shared = DataStore()
    
    let eventAppeared = PassthroughSubject<Event?, Never>()
    let notesChanged = PassthroughSubject<[Event], Never>()
    let unreadCount = CurrentValueSubject<Int, Never>(0)
    var didRestoreScrollPosition = false
    
    private var lastFiveEvents:[Event] = []
    var mostRecentEvent:Event?
        
    private var subscriptions = Set<AnyCancellable>()
    private let defaults: UserDefaults
    
    var restoreScrollToId: String? {
        set { defaults.set(newValue, forKey: "restoreScrollToId") }
        get { defaults.string(forKey: "restoreScrollToId") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        addSubscriptions()
    }
    
    func addSubscriptions() {
        
        // STORE MOST RECENT READ EVENT
        // + TRACK IF WE RESTORED YET
        eventAppeared
            .removeDuplicates()
            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [unowned self] appeared in
                guard self.mostRecentEvent != nil else {
                    self.mostRecentEvent = appeared
                    return
                }
                self.mostRecentEvent = self.mostRecentEvent!.created_at > appeared.created_at ? self.mostRecentEvent : appeared
            })
            .store(in: &subscriptions)
        
        // KEEP TRACK OF LAST 6 EVENTS
        // TO FETCH #E AND P's (NOT HERE)
        eventAppeared
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [unowned self] event in
                self.lastFiveEvents.append(event)
                if (self.lastFiveEvents.count > 6) {
                    _ = self.lastFiveEvents.removeFirst()
                }
            }
            .store(in: &subscriptions)
        
        // AFTER 0.2 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        eventAppeared
            .removeDuplicates()
            .compactMap { $0 }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.current)
            .throttle(for: .seconds(1), scheduler: RunLoop.current, latest: true)
            .sink { [unowned self] event in
//                print("🟠🟠 fetching for ids: \(ids(self.lastFiveEvents))")
//                sendNotification(.requestForJustAppeared, self.lastFiveEvents)
                
//                if (!self.didRestore.value) {
//                    self.didRestore.send(true)
//                }
//                else {
//                    self.selectedItemId = event.id!
//                }
                self.restoreScrollToId = event.id!
            }
            .store(in: &subscriptions)
        
        
        // WHEN NOTES ARE CHANGED, USE LAST READ INDEX TO TRACK HOW MANY UNREAD THERE ARE
        // SAVE IN self.unReadCount
        notesChanged
            .combineLatest(eventAppeared)
            .debounce(for: .seconds(0.05), scheduler: RunLoop.current)
            .map({ [unowned self] (notes, mostRecentReadEvent) in
                return (notes.filter { $0.created_at > (self.mostRecentEvent?.created_at ?? 0) })
            })
            .removeDuplicates()
            .sink(receiveValue: { [unowned self] unreadNotes in
                print("🟣🟣🟣 (notesChanged) unreadNotes.count: \(unreadNotes.count)")
                if (self.unreadCount.value != unreadNotes.count) {
                    self.objectWillChange.send()
                    self.unreadCount.send(unreadNotes.count)
                }
            })
            .store(in: &subscriptions)
    }
}
