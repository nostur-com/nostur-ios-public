//
//  Bookmark+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/11/2023.
//
//

import SwiftUI
import CoreData

@objc(Bookmark)
public class Bookmark: NSManagedObject {

    
    // -- MARK: Local - unsynced fields
    var event: Event?
    var nrPost: NRPost?
}

extension Bookmark {
    
    // MARK: DB functions
    static func fetchAll(context: NSManagedObjectContext) -> [Bookmark] {
        let fr = Bookmark.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }
    
    static func hasBookmark(eventId: String, context: NSManagedObjectContext) -> Bool {
        let fr = Bookmark.fetchRequest()
        fr.predicate = NSPredicate(format: "eventId == %@", eventId)
        
        return (try? context.fetch(fr).first) != nil        
    }
    
    static func fetchColor(eventId: String, context: NSManagedObjectContext) -> Color {
        let fr = Bookmark.fetchRequest()
        fr.predicate = NSPredicate(format: "eventId == %@", eventId)
        
        if let bookmark = try? context.fetch(fr).first {
            return bookmark.color
        }
        return .orange
    }
    
    static func removeBookmark(eventId: String, context: NSManagedObjectContext) {
        let fr = Bookmark.fetchRequest()
        fr.predicate = NSPredicate(format: "eventId == %@", eventId)
        
        if let bookmark = try? context.fetch(fr).first {
            context.delete(bookmark)
        }
    }
    
    // MARK: UI functions
    @MainActor static func addBookmark(_ nrPost: NRPost, color: Color = .orange) {
        sendNotification(.postAction, PostActionNotification(type: .bookmark(color), eventId: nrPost.id, bookmarked: true))
        bg().perform {
            let bookmark = Bookmark(context: bg())
            bookmark.eventId = nrPost.id
            bookmark.json = nrPost.event?.toNEvent().eventJson()
            bookmark.createdAt = .now
            bookmark.color = color
            bg().transactionAuthor = "addBookmark"
            DataProvider.shared().save()
            bg().transactionAuthor = nil
        }
    }
    
    @MainActor static func removeBookmark(_ nrPost: NRPost) {
        sendNotification(.postAction, PostActionNotification(type: .bookmark(.orange), eventId: nrPost.id, bookmarked: false))
        bg().perform {
            Bookmark.removeBookmark(eventId: nrPost.id, context: bg())
            bg().transactionAuthor = "removeBookmark"
            DataProvider.shared().save()
            bg().transactionAuthor = nil
        }
    }
    
    @MainActor static func updateColor(_ eventId: String, color: Color = .orange) {
        sendNotification(.postAction, PostActionNotification(type: .bookmark(color), eventId: eventId, bookmarked: true))
        bg().perform {
            let fr = Bookmark.fetchRequest()
            fr.predicate = NSPredicate(format: "eventId == %@", eventId)
            
            if let bookmark = try? bg().fetch(fr).first {
                bookmark.color = color
                bg().transactionAuthor = "updateColor"
                DataProvider.shared().save()
                bg().transactionAuthor = nil
            }
        }
    }
}
