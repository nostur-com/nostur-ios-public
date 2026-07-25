//
//  ReactionHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

/// Kinds that mark a kind-7 as a DM / private-message reaction (NIP-25 `k` tag or target event).
let DM_REACTION_TARGET_KINDS: Set<Int64> = [4, 14, 15]

/// Classify whether a kind-7 is a DM reaction.
///
/// Cost:
/// - `k` tag present → O(1), no fetch
/// - public (not giftwrapped) missing `k` → post reaction, no fetch
/// - giftwrapped missing `k` → one indexed target lookup by `e` id
/// - target missing → post reaction (safe default for private post likes)
func isDMReactionEvent(
    nEvent: NEvent,
    savedEvent: Event,
    wrapId: String?,
    context: NSManagedObjectContext
) -> Bool {
    guard nEvent.kind == .reaction else { return false }

    let k = savedEvent.kTag
    if DM_REACTION_TARGET_KINDS.contains(k) {
        return true
    }
    // Explicit non-DM k-tag (e.g. k=1 for a private reply reaction)
    if k != 0 {
        return false
    }

    // No k-tag: public reactions are never DMs
    guard wrapId != nil else { return false }

    // Ambiguous giftwrap without k: resolve target by last e-tag
    guard let targetId = nEvent.lastE() else { return false }
    guard let target = Event.fetchEvent(id: targetId, context: context) else {
        // Target not local yet → default to post reaction
        return false
    }

    if target.groupId != nil || DM_REACTION_TARGET_KINDS.contains(target.kind) {
        // Backfill k for future cheap classification / migrations
        if savedEvent.kTag == 0 {
            savedEvent.kTag = target.kind
        }
        return true
    }
    return false
}

func handleReaction(nEvent: NEvent, savedEvent: Event, wrapId: String? = nil, isDM: Bool = false, context: NSManagedObjectContext) {
    // Only post reactions (not DM / NIP-17 private-message reactions)
    guard nEvent.kind == .reaction, !isDM else { return }
    
    if let lastE = nEvent.lastE() {
        savedEvent.reactionToId = lastE

        if savedEvent.otherPubkey == nil, let lastP = nEvent.lastP() {
            savedEvent.otherPubkey = lastP
        }
    }
    
    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
    Event.updateLikeCountCache(savedEvent, content: nEvent.content, context: context)
    if let otherPubkey = savedEvent.otherPubkey, AccountsState.shared.bgAccountPubkeys.contains(otherPubkey) {
        // TODO: Check if this works for own accounts, because import doesn't happen when saved local first?
        ViewUpdates.shared.feedUpdates.send(FeedUpdate(type: .Reactions, accountPubkey: otherPubkey))
    }
    if let reactionToId = savedEvent.reactionToId {
        ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Reactions, eventId: reactionToId))
        
        // Update own reactions cache
        if nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
            let reactionContent = nEvent.content
            Task { @MainActor in
                accountCache()?.addReaction(reactionToId, reactionType: reactionContent)
                sendNotification(.postAction, PostActionNotification(type: .reacted(nil, reactionContent), eventId: reactionToId))
            }
        }
    }
}

func handleDMReaction(nEvent: NEvent, savedEvent: Event, wrapId: String? = nil, isDM: Bool = false, context: NSManagedObjectContext) {
    guard nEvent.kind == .reaction, isDM else { return }
    
    if let lastE = nEvent.lastE() {
        savedEvent.reactionToId = lastE

        if savedEvent.otherPubkey == nil, let lastP = nEvent.lastP() {
            savedEvent.otherPubkey = lastP
        }
    }
}
