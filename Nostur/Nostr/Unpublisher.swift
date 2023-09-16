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
class Unpublisher {
    
    enum type {
        case other
        case contactList
    }
    
    let PUBLISH_DELAY:Double = 9.0 // SECONDS
    var timer:Timer?
    var viewContext:NSManagedObjectContext
    var queue:[Unpublished] = []
    let sp:SocketPool = .shared
    
    static var shared = Unpublisher()
    
    init() {
        self.viewContext = DataProvider.shared().viewContext
        self.timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(onNextTick), userInfo: nil, repeats: true)
        self.timer?.tolerance = 1.0
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    // Removes any existing ofType from the queue, before adding this one
    // For example after rapid follow/unfollow, creates new clEvents, only publish the last one
    // Also, we can have multiple of same type from different accounts, so check if pubkey is the same too before removing
    func publishLast(_ nEvent:NEvent, ofType: Unpublisher.type) -> UUID {
        queue.removeAll(where: { $0.type == ofType && nEvent.publicKey == $0.nEvent.publicKey })
        let cancellationId = UUID()
        queue.append(Unpublished(type: ofType, cancellationId: cancellationId, nEvent: nEvent, createdAt: Date.now))
        return cancellationId
    }
    
    func publish(_ nEvent:NEvent, cancellationId:UUID? = nil) -> UUID {
        // if an event with the same id is already in the queue, replace it and reset the timer
        if queue.first(where: { $0.nEvent.id == nEvent.id }) != nil {
            queue = queue.filter { $0.nEvent.id != nEvent.id } // remove existing
            
            
            L.og.info("Going to publish event.id after 9 sec: \(nEvent.id) - replaced existing event in queue")
            let cancellationId = cancellationId ?? UUID()
            
            // add the new event
            queue.append(Unpublished(type:.other, cancellationId: cancellationId, nEvent: nEvent, createdAt: Date.now))
            return cancellationId
        }
        
        L.og.info("Going to publish event.id after 9 sec: \(nEvent.id)")
        let cancellationId = cancellationId ?? UUID()
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
    
    func sendNow(_ cancellationId:UUID) -> Bool {
        let beforeCount = queue.count
        if let event = queue.first(where: { $0.cancellationId == cancellationId })?.nEvent {
            queue.removeAll(where: { $0.cancellationId == cancellationId })
            sendToRelays(event)
        }
        return beforeCount != queue.count
    }
    
    @objc func onNextTick(notification: NSNotification) {
        guard !queue.isEmpty else { return }
        
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
        guard !queue.isEmpty else { return }
        queue.forEach({ sendToRelays($0.nEvent) })
        queue.removeAll()
        
        // lets also save context here...
        L.og.debug("DataProvider.shared().save() from Unpublisher.appMovedToBackground ")
        DataProvider.shared().save()
    }
    
    private func sendToRelays(_ nEvent:NEvent) {
        if nEvent.kind == .nwcRequest {
            L.og.info("⚡️ Sending .nwcRequest to NWC relay")
            sp.sendMessage(ClientMessage(onlyForNWCRelay: true, message: nEvent.wrappedEventJson()), accountPubkey: nEvent.publicKey)
            return
        }

        let bgContext = DataProvider.shared().bg
        
        // Always save event first
        // Save or update event
        
        bgContext.perform {
            if let dbEvent = try? Event.fetchEvent(id: nEvent.id, context: bgContext) {
                // We already have it in db
                
                DispatchQueue.main.async {
                    sendNotification(.publishingEvent, nEvent.id) // to remove 'undo send' from view
                    self.sp.sendMessage(ClientMessage(message: nEvent.wrappedEventJson()), accountPubkey: nEvent.publicKey)
                }
                
                dbEvent.flags = ""
                dbEvent.cancellationId = nil
                dbEvent.updateNRPost.send(dbEvent)
            }
            else {
                // Event not in db yet
                let savedEvent = Event.saveEvent(event: nEvent)
                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                if nEvent.kind == .reaction {
                    do {
                        try Event.updateReactionTo(savedEvent, context: bgContext)
                    } catch {
                        L.og.error("🦋🦋🔴🔴🔴 problem updating Like relation .id \(nEvent.id)")
                    }
                }
                
                DataProvider.shared().bgSave()
                if ([1,6,9802,30023].contains(savedEvent.kind)) {
                    DispatchQueue.main.async {
                        sendNotification(.newPostSaved, savedEvent)
                    }
                }
                DispatchQueue.main.async {
                    sendNotification(.publishingEvent, nEvent.id) // to remove 'undo send' from view
                    self.sp.sendMessage(ClientMessage(message: nEvent.wrappedEventJson()), accountPubkey: nEvent.publicKey)
                }
            }
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
