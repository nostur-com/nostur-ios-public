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
    
    let PUBLISH_DELAY = 9.0 // SECONDS
    var timer:Timer?
    var viewContext:NSManagedObjectContext
    var queue:[Unpublished] = []
    let sp:SocketPool = .shared
    
    static var shared = Unpublisher(viewContext: EventsProvider.shared.container.viewContext)
    
    init(viewContext:NSManagedObjectContext) {
        self.viewContext = viewContext
        self.timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(onNextTick), userInfo: nil, repeats: true)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    func publish(_ nEvent:NEvent) -> UUID {
        print("going to publish")
        let cancellationId = UUID()
        queue.append(Unpublished(cancellationId: cancellationId, nEvent: nEvent, createdAt: Date.now))
        return cancellationId
    }
    
    func publishNow(_ nEvent:NEvent) {
        sendToRelays(nEvent)
    }
    
    func cancel(_ cancellationId:UUID) -> Bool {
        print("unpublishing")
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
    }
    
    private func sendToRelays(_ nEvent:NEvent) {
        // Always save event first
        if try! Event.fetchEvent(id: nEvent.id, context: viewContext) == nil {
            let savedEvent = Event.saveEvent(event: nEvent, context: viewContext)
            do { try viewContext.save() }
            catch {
                print("🔴🔴🔴🔴🔴 COULD NOT SAVE EVENT 🔴🔴🔴🔴🔴")
                print(error)
                return
            }
            sp.sendMessage(ClientMessage(message: savedEvent.toNEvent().wrappedEventJson()))
        }
        else {
            sp.sendMessage(ClientMessage(message: nEvent.wrappedEventJson()))
        }
    }
}

extension Unpublisher {
    struct Unpublished {
        var cancellationId:UUID
        var nEvent:NEvent
        var createdAt:Date
    }
}
