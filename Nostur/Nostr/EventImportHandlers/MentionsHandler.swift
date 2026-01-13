//
//  MentionsHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/01/2026.
//

import Foundation
import CoreData

let SUPPORTED_KINDS_CAN_HAVE_MENTIONS: Set<NEventKind> = [.textNote, .comment, .article]
let SUPPORTED_KINDS_CAN_BE_MENTIONED: Set<NEventKind> = [.textNote, .comment, .article, .shortVoiceMessage, .shortVoiceMessageComment, .highlight, .picture, .shortVideos, .video]

// mentions (q tags)
func handleMentions(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    
    // First check is this post mentionining other events we already have in db? to update mentionsCount
    if SUPPORTED_KINDS_CAN_HAVE_MENTIONS.contains(nEvent.kind) {
        // if event doesn't event have nostr: or q tags we don't need to contue
        guard !savedEvent.fastQs.isEmpty else { return }
        guard nEvent.content.contains("nostr:n") else { return } // should have at least a note or nevent
        
        
        for qTag in savedEvent.fastQs {
            if let mentionedEvent = Event.fetchEvent(id: qTag.1, context: context) {
                mentionedEvent.mentionsCount = (mentionedEvent.mentionsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: mentionedEvent.id, mentions: mentionedEvent.mentionsCount))
            }
        }
    }
    
    
    // Then check if this is a post that is mentioned by events we already have in DB, to set mentionsCount
    if SUPPORTED_KINDS_CAN_BE_MENTIONED.contains(nEvent.kind) {
        let mentions = Event.fetchMentions(id: nEvent.id, after: nEvent.createdAt.timestamp, context: context)
        let mentionsCount = Int64(mentions.count)
        
        if let mentionedEvent = Event.fetchEvent(id: nEvent.id, context: context) {
            mentionedEvent.mentionsCount = mentionsCount
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: mentionedEvent.id, mentions: mentionsCount))
        }
    }
}
