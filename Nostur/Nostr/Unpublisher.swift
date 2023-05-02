//
//  Unpublisher.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2023.
//

import Foundation
import CoreData
import UIKit

/**
 Publish events after 9 seconds, gives time to undo before sending. (accidental likes etc)
 also immediatly publishes all when app goes to background
 
 To publish:
 let cancellationId = up.publish(nEvent)
 event.liked = true
 
 To cancel:
 if cancellationId != nil && up.cancel(cancellationId) {
 event.liked = false
 }
 
 */
class Unpublisher: ObservableObject {
    
    enum type {
        case other
        case contactList
    }
    
    let PUBLISH_DELAY = 9.0 // SECONDS
    var timer:Timer?
    var viewContext:NSManagedObjectContext
    var queue:[Unpublished] = []
    let sp:SocketPool = .shared
    
    static var shared = Unpublisher()
    
    init() {
        self.viewContext = DataProvider.shared().viewContext
        self.timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(onNextTick), userInfo: nil, repeats: true)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    // Removes any existing ofType from the queue, before adding this one
    // For example after rapid follow/unfollow, creates new clEvents, only publish the last one
    func publishLast(_ nEvent:NEvent, ofType: Unpublisher.type) -> UUID {
        queue.removeAll(where: { $0.type == ofType })
        let cancellationId = UUID()
        queue.append(Unpublished(type: ofType, cancellationId: cancellationId, nEvent: nEvent, createdAt: Date.now))
        return cancellationId
    }
    
    func publish(_ nEvent:NEvent) -> UUID {
        print("going to publish")
        let cancellationId = UUID()
        queue.append(Unpublished(type:.other, cancellationId: cancellationId, nEvent: nEvent, createdAt: Date.now))
        return cancellationId
    }
    
    func publishNow(_ nEvent:NEvent) {
        sendToRelays(nEvent)
    }
    
    func cancel(_ cancellationId:UUID) -> Bool {
        let beforeCount = queue.count
        queue.removeAll(where: { $0.cancellationId == cancellationId })
        return beforeCount != queue.count
    }
    
    @objc func onNextTick(notification: NSNotification) {
        guard queue.count != 0 else { return }
        
        queue
            .filter { $0.createdAt < Date.now.addingTimeInterval(-(PUBLISH_DELAY)) }
            .forEach({ item in
                sendToRelays(item.nEvent)
                queue.removeAll { q in
                    q.cancellationId == item.cancellationId
                }
            })
    }
    
    @objc func appMovedToBackground(notification: NSNotification) {
        guard queue.count != 0 else { return }
        queue.forEach({ sendToRelays($0.nEvent) })
        queue.removeAll()
        
        // lets also save context here...
        DataProvider.shared().save()
    }
    
    private func sendToRelays(_ nEvent:NEvent) {
        // Always save event first
        if try! Event.fetchEvent(id: nEvent.id, context: viewContext) == nil {
            let savedEvent = Event.saveEvent(event: nEvent, context: viewContext, skipRelatedUpdate: true)
            
            // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
            if nEvent.kind == .reaction {
                do { try Event.updateReactionTo(savedEvent, context: viewContext) } catch {
                    print("🦋🦋🔴🔴🔴 problem updating Like relation .id \(nEvent.id)")
                }
            }
            do {
                if viewContext.hasChanges {
                    try viewContext.save()
                }
                // dont wait for background importer, show immediatly on screen (only (re)posts .kind)
                if ([1,6,9802].contains(savedEvent.kind)) {
                    sendNotification(.newPostSaved, savedEvent)
                }
            }
            catch {
                print("🔴🔴🔴🔴🔴 COULD NOT SAVE EVENT 🔴🔴🔴🔴🔴")
                print(error)
                return
            }
            Importer.shared.existingIds.insert(savedEvent.id)
            sp.sendMessage(ClientMessage(message: savedEvent.toNEvent().wrappedEventJson()))
        }
        else {
            Importer.shared.existingIds.insert(nEvent.id)
            sp.sendMessage(ClientMessage(message: nEvent.wrappedEventJson()))
        }
    }
}

extension Unpublisher {
    struct Unpublished {
        var type:Unpublisher.type
        var cancellationId:UUID
        var nEvent:NEvent
        var createdAt:Date
    }
}
