//
//  RepostHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

// Returns inner reposted Event or nil`
func handleRepost(_ event: NEvent, relays: String, bgContext: NSManagedObjectContext) throws -> Event? {
    if event.kind == .repost && (event.content.prefix(2) == #"{""# || event.content == "") {
        if event.content == "" {
            if let firstE = event.firstE() {
                return Event.fetchEvent(id: firstE, context: bgContext)
            }
            return nil
        }
        else if let noteInNote = try? Importer.shared.decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
            if !Event.eventExists(id: noteInNote.id, context: bgContext) {
                
                guard try noteInNote.verified() else {
#if DEBUG
                    L.importing.info("🔴🔴😡😡 hey invalid sig yo 😡😡")
#endif
                    throw ImportErrors.InvalidSignature
                }
                let kind6firstQuote = Event.saveEvent(event: noteInNote, relays: relays, context: bgContext)
                
                FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                    NeedsUpdateInfo(event: kind6firstQuote)
                )
            }
            else {
                Event.updateRelays(noteInNote.id, relays: relays, context: bgContext)
            }
        }
    }
    return nil
}

public enum ImportErrors: Error {
    
    case InvalidSignature
}
