//
//  DMfunctions.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/05/2023.
//


import Foundation

func computeOnlyMostRecentAll(sent:[Event],received:[Event],pubkey:String) -> [String: ([Event], Bool, Int, Int64, Event)] {
    var recent = [String: ([Event], Bool, Int, Int64, Event)]() // dict: [pubkey: [dm], isAccepted, unreadCount, rootDM.createdAt, rootDM]
    
    // combine all dms, initiated by me and others, and sort them
    let allDms = (sent + received)
        .sorted(by: { $0.created_at < $1.created_at }) // Root DMs will be index 0
    
    
    for dm in allDms {
        if dm.pubkey == pubkey { // dm by me (take event.firstP)
            if let contactPubkey = dm.firstP() {
                if recent[contactPubkey] == nil {
                    recent[contactPubkey] = ([dm], true, 0, dm.created_at, dm) // sent so consider accepted
                }
                else {
                    let dms = recent[contactPubkey]!.0 + [dm]
                    let unread = recent[contactPubkey]!.2 + 0 // +0 because sent by me.
                    recent[contactPubkey] = (dms, true, unread, recent[contactPubkey]!.3, recent[contactPubkey]!.4) // maybe this dict key was received before, but now also responded so consider accepted
                }
            }
        }
        else { // dm by someone else (take event.pubkey)
            if recent[dm.pubkey] == nil {
                let count = dm.created_at > dm.lastSeenDMCreatedAt ? 1 : 0
                recent[dm.pubkey] = ([dm], dm.dmAccepted, count, dm.created_at, dm) // The first, rootDM, controls isAccepted or not
                // check rootDM.lastSeenDMCreatedAt for +1 or +0
            }
            else {
                let current = recent[dm.pubkey]
                let count = dm.created_at > current?.0.first?.lastSeenDMCreatedAt ?? 0 ? 1 : 0
                let dms = current!.0 + [dm]
                let unread = current!.2 + count // check rootDM.lastSeenDMCreatedAt for +1 or +0
                let isAccepted = current!.1 || (current?.0.first?.dmAccepted ?? false)
                recent[dm.pubkey] = (dms, isAccepted, unread, recent[dm.pubkey]!.3, recent[dm.pubkey]!.4)
            }
        }
    }
    
    return recent
}

func computeOnlyMostRecentAccepted(_ onlyMostRecentAll:[String: ([Event], Bool, Int, Int64, Event)]) -> [(Event, Int)] {
    onlyMostRecentAll
        .filter { $0.value.1 == true }
        .compactMap {
            // Take newest message from the conversation and unread count
            if let newestMessage = $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first {
                return (
                    newestMessage, // newest message
                    $0.value.2 // unread count
                )
            }
            else {
                return nil
            }
        }
        .sorted(by: { $0.0.created_at > $1.0.created_at }) // not sure if need to sort again?
}

func computeOnlyMostRecentRequests(_ onlyMostRecentAll:[String: ([Event], Bool, Int, Int64, Event)]) -> [(Event, Int64)] {
    // dict: [pubkey: [dm], isAccepted, unreadCount, rootDM.createdAt, rootDM]
    onlyMostRecentAll
        .filter { !$0.value.4.isSpam }
        .filter { $0.value.1 == false }
        .compactMap {
            if let first = $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first {
                return (first, $0.value.3)
            }
            return nil
        }
        .sorted(by: { $0.0.created_at > $1.0.created_at }) // not sure if need to sort again?
}

func computeOnlyMostRecentAcceptedTotalUnread(_ onlyMostRecentAccepted:[(Event, Int)]) -> Int {
    onlyMostRecentAccepted.reduce(0) { (partialResult, recentDMtuple) in
        let (_, unread) = recentDMtuple
        return partialResult + unread
    }
}

func computeRequestTotalUnread(_ onlyMostRecentRequests:[(Event, Int64)], lastSeenDMRequestCreatedAt:Int64) -> Int {
    return onlyMostRecentRequests.reduce(0) { (partialResult, requestDMtuple) in
        let (_, createdAt) = requestDMtuple
        if (createdAt > lastSeenDMRequestCreatedAt) {
            return partialResult + 1
        }
        return partialResult
    }
}
