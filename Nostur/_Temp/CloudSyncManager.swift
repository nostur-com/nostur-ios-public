//
//  CloudSyncManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2024.
//

import Foundation
import CoreData

class CloudSyncManager {
    
    static let shared = CloudSyncManager()
    
    private let context = bg()
    private let viewUpdates = ViewUpdates.shared
    
    let bookmarks = BookmarkBgFetchRequest() // WTF if we remove this context.deletedObjects is always 0
    let accounts = CloudAccountBgFetchRequest() // WTF if we remove this context.deletedObjects is always 0
    let relays = CloudRelayBgFetchRequest() // WTF if we remove this context.deletedObjects is always 0
    let dmStates = CloudDMStateFetchRequest() // WTF if we remove this context.deletedObjects is always 0
    
    private init() {
        self.listenForChanges()
    }
    
    func listenForChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextObjectsDidChange(notification:)),
            name: .NSManagedObjectContextObjectsDidChange,
            object: self.context
        )
    }
    
    @objc func contextObjectsDidChange(notification: NSNotification) {
        guard let userInfo = notification.userInfo else { return }

        // Process Bookmark Changes (toggle bookmark buttons in view)
        processEntityChanges(userInfo: userInfo, entity: Bookmark.self, insertHandler: handleBookmarkInsert, deleteHandler: handleBookmarkDelete)

        // Process CloudAccount Changes (toggle follow state buttons)
        processEntityChanges(userInfo: userInfo, entity: CloudAccount.self, updateHandler: handleCloudAccountUpdate)
    }

    func processEntityChanges<T: NSManagedObject>(userInfo: [AnyHashable: Any], entity: T.Type, insertHandler: ((T) -> Void)? = nil, updateHandler: ((T) -> Void)? = nil, deleteHandler: ((T) -> Void)? = nil) {
        if let insertHandler, let inserts = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            inserts.compactMap { $0 as? T }.forEach(insertHandler)
        }
        if let updateHandler, let updates = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            updates.compactMap { $0 as? T }.forEach(updateHandler)
        }
        if let deleteHandler, let deletes = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            deletes.compactMap { $0 as? T }.forEach(deleteHandler)
        }
    }

    // -- MARK: Bookmark
    func handleBookmarkInsert(_ bookmark: Bookmark) {
        guard let eventId = bookmark.eventId else { return }
        Task { @MainActor in
            viewUpdates.bookmarkUpdates.send(BookmarkUpdate(id: eventId, isBookmarked: true))
            if let accountCache = NRState.shared.loggedInAccount?.accountCache {
                bg().perform {
                    accountCache.addBookmark(eventId, color: bookmark.color)
                }
            }
        }
    }

    func handleBookmarkDelete(_ bookmark: Bookmark) {
        // Handle Bookmark delete
        guard let eventId = bookmark.eventId else { return }
        Task { @MainActor in
            viewUpdates.bookmarkUpdates.send(BookmarkUpdate(id: eventId, isBookmarked: false))
            if let accountCache = NRState.shared.loggedInAccount?.accountCache {
                bg().perform {
                    accountCache.removeBookmark(eventId)
                }
            }
        }
    }

    // -- MARK: CloudAccount
    func handleCloudAccountUpdate(_ profileInfo: CloudAccount) {
        // Handle CloudAccount update
        // Test with view update follow button
    }
}
