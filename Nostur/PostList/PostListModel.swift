//
//  PostListModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//

import Foundation
import Combine
import CoreData

final class PostListModel: ObservableObject, Identifiable, Equatable {
    static func == (lhs: PostListModel, rhs: PostListModel) -> Bool {
        return lhs.listState.objectID == rhs.listState.objectID
    }
    
    static func fromDb(pubkey:String, listId:String, context:NSManagedObjectContext) -> PostListModel {
        var listState:ListState?
        
        listState = ListState.fetchListState(pubkey, listId: listId, context: context)
        
        if (listState == nil) {
            listState = ListState(context: context)
            listState!.listId = listId
            listState!.pubkey = pubkey
            listState!.updatedAt = Date.now
            do {
                try context.save()
            }
            catch {
                print("could not save new listState")
            }
        }
            
        let model = PostListModel(listState:listState!)
        
        if let lastAppearedId = listState!.lastAppearedId {
            if let lastAppeared = try? Event.fetchEvent(id: lastAppearedId, context: context) {
                model.lastAppearedSubject.send(lastAppeared)
                model.lastAppearedAnchorSubject.send(listState!.lastAppearedAtAnchor)
            }
//            model.lastAppeared = try? Event.fetchEvent(id: lastAppearedId, context: context)
        }
        if let mostRecentAppearedId = listState!.mostRecentAppearedId {
            if let mostRecent = try? Event.fetchEvent(id: mostRecentAppearedId, context: context) {
                model.mostRecentReadSubject.send(mostRecent)
            }
        }
        
        return model
    }

    var listState:ListState
    var id:String { listState.listId }
    
    
//    var lastAppearedAtAnchor = "BOTTOM"
//    var lastAppearedEvent:Event?
//    var lastFiveEvents:[Event] = []
//    var mostRecentAppearedEvent:Event?
    
    let lastAppearedSubject = CurrentValueSubject<Event?, Never>(nil)
    let lastAppearedAnchorSubject = CurrentValueSubject<String, Never>("BOTTOM")
    
    let mostRecentReadSubject = CurrentValueSubject<Event?, Never>(nil)
    let unreadCountSubject = CurrentValueSubject<Int, Never>(0)
    
    let lastFiveEventsSubject = CurrentValueSubject<[Event], Never>([])
    let visiblePostsSubject = CurrentValueSubject<[Event], Never>([])
//    @Published var visiblePosts:[Event] = []
//    @Published var mostRecentReadIndexX = 0
 
    private var subscriptions = Set<AnyCancellable>()
    
    init(listState:ListState) {
        self.listState = listState
//        self.unreadCount.send(listState.unreadCount) // niet meer nodig?
        addSubscriptions()
    }
    
    func addSubscriptions() {
        storeLastAppeared()
        storeMostRecentRead()
        saveListState()
        updateUnreadCount()
        trackLast6Events()
        requestFooterCounters()
        setVisiblePosts()
    }
    
    // can be old or new, depending on scroll back or not
    func storeLastAppeared() {
        // STORE MOST RECENT READ EVENT
        // + TRACK IF WE RESTORED YET
        lastAppearedSubject
//            .removeDuplicates()
//            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [weak self] post in
                guard let self = self else { return }
                guard let lastAppearedEvent = self.lastAppearedSubject.value else {
                    // FIRST EVENT
                    self.lastAppearedSubject.send(post)
                    self.lastAppearedAnchorSubject.send("BOTTOM")
                    return
                }
                
                // ALL OTHER EVENTS:
                
                self.objectWillChange.send()
                self.lastAppearedAnchorSubject.send(post.created_at > lastAppearedEvent.created_at ? "BOTTOM" : "TOP")
//                self.objectWillChange.send()
//                self.lastAppearedSubject.send(post)
                
//                guard post.created_at > (self.mostRecentAppeared?.created_at ?? 0) else { return }
//                self.mostRecentAppeared = post
            })
            .store(in: &subscriptions)
    }
    
    // .created_at is always newest
    func storeMostRecentRead() {
        lastAppearedSubject
//            .removeDuplicates()
//            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [weak self] post in
                guard let self = self else { return }
                                
                print("🟢🟢🟢🟢sd🟢🟢 \(post.created_at) > \((self.mostRecentReadSubject.value?.created_at ?? 0))")
                guard post.created_at > (self.mostRecentReadSubject.value?.created_at ?? 0) else { return }
                self.objectWillChange.send()
                self.mostRecentReadSubject.send(post)
            })
            .store(in: &subscriptions)
    }
    
    func saveListState() {
        lastAppearedSubject
            .throttle(for: .seconds(1), scheduler: RunLoop.current, latest: true)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.listState.lastAppearedId = self.lastAppearedSubject.value?.id
                self.listState.mostRecentAppearedId = self.mostRecentReadSubject.value?.id
                self.listState.lastAppearedAtAnchor = self.lastAppearedAnchorSubject.value
                self.listState.updatedAt = Date.now
                self.listState.unreadCount = self.unreadCountSubject.value
                do {
                    try self.listState.managedObjectContext?.save()
                    print ("💾 LIST STATE SAVED :D")
                }
                catch {
                    print("Error saving list state \(self.id) \(self.listState.pubkey)")
                }
            }
            .store(in: &subscriptions)
    }
    
    func setVisiblePosts() {
        visiblePostsSubject
            .sink(receiveValue: {  [weak self] events in
                guard let self = self else { return }
                self.objectWillChange.send()
            })
            .store(in: &subscriptions)
    }
    
    func updateUnreadCount() {
        // Only if mostRecent read changes?
        mostRecentReadSubject
            .removeDuplicates()
//            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [weak self] mostRecentPost in
                guard let self = self else { return }
                guard let lastAppeared = self.lastAppearedSubject.value else { return }
                
                // SO TAKE TOTAL ON SCREEN
                // SUBSTRACT LAST APPEARED INDEX
                // BUT ONLY CHANGE COUNTER lastAppearedCreatedAt is NEWER
//                guard lastAppeared.created_at >= (self.mostRecentAppeared?.created_at ?? 0) else { return }

                // COUNT FROM WHICH EVENT?
                // IF LAST APPEARED IS NEWER THEN MOST READ, TAKE THAT
                // ELSE COUNT FROM MOST RECENT
                let countFromEvent = lastAppeared.created_at >= mostRecentPost.created_at ? lastAppeared : mostRecentPost
                let mostRecentReadIndex = self.visiblePostsSubject.value.map { $0.id }.firstIndex(of: countFromEvent.id) ?? 0
                
                self.objectWillChange.send()
                self.unreadCountSubject.send(self.visiblePostsSubject.value.count - mostRecentReadIndex - 1)
//                self.mostRecentReadIndexX = mostRecentReadIndex
//                if (self.unreadCount.value != (visiblePosts.count - mostRecentReadIndex - 1)) {
//                    self.objectWillChange.send()
//                    self.unreadCount.send(visiblePosts.count - mostRecentReadIndex - 1)
//                }

            })
            .store(in: &subscriptions)
        
        visiblePostsSubject
            .sink(receiveValue: {  [weak self] events in
                guard let self = self else { return }
                guard let mostRecent = self.mostRecentReadSubject.value else {
                    self.objectWillChange.send()
                    self.unreadCountSubject.send(events.count)
                    return
                }
                
                let mostRecentReadIndex = events.map { $0.id }.firstIndex(of: mostRecent.id) ?? 0
                self.objectWillChange.send()
                self.unreadCountSubject.send(events.count - mostRecentReadIndex - 1)
            })
            .store(in: &subscriptions)
    }
    
    func trackLast6Events() {
        // KEEP TRACK OF LAST 6 EVENTS
        // TO FETCH #E AND P's (NOT HERE)
        // TODO: NEED THIS BACK
        // AFTER 0.2 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        lastAppearedSubject
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self = self else { return }
                var lastFive = self.lastFiveEventsSubject.value
                
                lastFive.append(event)
                if (lastFive.count > 6) {
                    self.lastFiveEventsSubject.send(Array(lastFive.suffix(5)))
                }
            }
            .store(in: &subscriptions)
    }
    
    func requestFooterCounters() {
        // AFTER 0.5 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        lastAppearedSubject
            .removeDuplicates()
            .compactMap { $0 }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.current)
            .throttle(for: .seconds(1), scheduler: RunLoop.current, latest: true)
            .sink { [weak self] event in
                guard let self = self else { return }
                sendNotification(.requestForJustAppeared, self.lastFiveEventsSubject.value)
            }
            .store(in: &subscriptions)
    }
    
    // TODO: ERGENS BIJ ON APP BACKGROUND SAVE TO DB
}
