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
            model.lastAppeared = try? Event.fetchEvent(id: lastAppearedId, context: context)
        }
        if let mostRecentAppearedId = listState!.mostRecentAppearedId {
            model.mostRecentAppeared = try? Event.fetchEvent(id: mostRecentAppearedId, context: context)
        }
        
        return model
    }

    var listState:ListState
    var id:String {
        listState.listId
    }
    var lastAppearedAtAnchor = "BOTTOM"
    var lastAppeared:Event?
    var lastFiveEvents:[Event] = []
    var mostRecentAppeared:Event?
    
    let setLastAppeared = PassthroughSubject<Event?, Never>()
    let updateUnreadCount = PassthroughSubject<[Event], Never>()
    let unreadCount = CurrentValueSubject<Int, Never>(0)
    
        
    private var subscriptions = Set<AnyCancellable>()
    
    init(listState:ListState) {
        self.listState = listState
//        self.unreadCount.send(listState.unreadCount) // niet meer nodig?
        addSubscriptions()
    }
    
    func addSubscriptions() {
        
        // STORE MOST RECENT READ EVENT
        // + TRACK IF WE RESTORED YET
        setLastAppeared
//            .removeDuplicates()
//            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [weak self] post in
                guard let self = self else { return }
                guard let lastAppeared = self.lastAppeared else {
                    self.lastAppeared = post
                    return
                }
                
//                self.objectWillChange.send()
                self.lastAppearedAtAnchor = post.created_at > lastAppeared.created_at ? "BOTTOM" : "TOP"
                self.lastAppeared = post
                
                guard post.created_at > (self.mostRecentAppeared?.created_at ?? 0) else { return }
                self.mostRecentAppeared = post
                
            })
            .store(in: &subscriptions)
        
        setLastAppeared
            .throttle(for: .seconds(1), scheduler: RunLoop.current, latest: true)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.listState.lastAppearedId = self.lastAppeared?.id
                self.listState.mostRecentAppearedId = self.mostRecentAppeared?.id
                self.listState.lastAppearedAtAnchor = self.lastAppearedAtAnchor
                self.listState.updatedAt = Date.now
                self.listState.unreadCount = self.unreadCount.value
                do {
                    try self.listState.managedObjectContext?.save()
                    print ("💾 LIST STATE SAVED :D")
                }
                catch {
                    print("Error saving list state \(self.id) \(self.listState.pubkey)")
                }
            }
            .store(in: &subscriptions)
        
        updateUnreadCount
//            .removeDuplicates()
//            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [weak self] visiblePosts in
                guard let self = self else { return }
                guard let lastAppeared = self.lastAppeared else { return }
                
                // SO TAKE TOTAL ON SCREEN
                // SUBSTRACT LAST APPEARED INDEX
                // BUT ONLY CHANGE COUNTER lastAppearedCreatedAt is NEWER
                guard lastAppeared.created_at >= (self.mostRecentAppeared?.created_at ?? 0) else { return }
                let lastAppearedIndex = visiblePosts.map { $0.id }.firstIndex(of: lastAppeared.id) ?? 0
                if (self.unreadCount.value != (visiblePosts.count - lastAppearedIndex - 1)) {
                    self.objectWillChange.send()
                    self.unreadCount.send(visiblePosts.count - lastAppearedIndex - 1)
                }
                
            })
            .store(in: &subscriptions)
        
        // KEEP TRACK OF LAST 6 EVENTS
        // TO FETCH #E AND P's (NOT HERE)
        // TODO: NEED THIS BACK
        // AFTER 0.2 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        setLastAppeared
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self = self else { return }
                self.lastFiveEvents.append(event)
                if (self.lastFiveEvents.count > 6) {
                    _ = self.lastFiveEvents = Array(self.lastFiveEvents.suffix(5))
                }
            }
            .store(in: &subscriptions)
        
        
        // AFTER 0.2 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        setLastAppeared
            .removeDuplicates()
            .compactMap { $0 }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.current)
            .throttle(for: .seconds(1), scheduler: RunLoop.current, latest: true)
            .sink { [weak self] event in
                guard let self = self else { return }
                sendNotification(.requestForJustAppeared, self.lastFiveEvents)
            }
            .store(in: &subscriptions)
    }
    
    // TODO: ERGENS BIJ ON APP BACKGROUND SAVE TO DB
}
