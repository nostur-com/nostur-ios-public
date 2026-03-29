//
//  PrivateInteractionHelper.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2026.
//

import Foundation
import NostrEssentials

// Sends an NEvent as a private (giftwrapped) interaction to the recipient's DM relays and own DM relays for backup
@MainActor
func sendPrivateInteraction(_ nEvent: NEvent, recipientPubkey: String) {
    guard let account = account(), !account.isNC else { return }
    guard let privKey = AccountManager.shared.getPrivateKeyHex(pubkey: account.publicKey),
          let ourkeys = try? Keys(privateKeyHex: privKey) else { return }
    
    var event = nEvent
    event.publicKey = account.publicKey
    let neEvent = event.toNostrEssentialsEvent()
    let rumorEvent = createRumor(neEvent)
    
    let ourPubkey = account.publicKey
    
    Task {
        let recipientRelays = await getDMrelays(for: recipientPubkey)
        let ownRelays = await getDMrelays(for: ourPubkey)
        
        guard !recipientRelays.isEmpty || !ownRelays.isEmpty else { return }
        
        // Wrap and send to self (backup)
        do {
            let selfWrap = try createGiftWrap(rumorEvent, receiverPubkey: ourPubkey, keys: ourkeys)
            let selfWrapId = selfWrap.fallbackId()
            
            await bg().perform {
                _ = Event.saveEvent(event: rumorEvent, wrapId: selfWrapId, context: bg())
                MessageParser.shared.pendingOkWrapToRumorIdMap[selfWrapId] = rumorEvent.fallbackId()
            }
            
            let relaysForSelf = ownRelays.isEmpty ? recipientRelays : ownRelays
            sendGiftWrapToRelays(wrappedEvent: selfWrap, relays: relaysForSelf)
        }
        catch {
            L.og.error("Error wrapping private interaction for self: \(error)")
        }
        
        // Wrap and send to recipient
        do {
            let recipientWrap = try createGiftWrap(rumorEvent, receiverPubkey: recipientPubkey, keys: ourkeys)
            let relaysForRecipient = recipientRelays.isEmpty ? ownRelays : recipientRelays
            MessageParser.shared.pendingOkWrapToRumorIdMap[recipientWrap.fallbackId()] = rumorEvent.fallbackId()
            sendGiftWrapToRelays(wrappedEvent: recipientWrap, relays: relaysForRecipient)
        }
        catch {
            L.og.error("Error wrapping private interaction for recipient: \(error)")
        }
    }
}

private func sendGiftWrapToRelays(wrappedEvent: NostrEssentials.Event, relays: Set<String>) {
    for relay in relays {
        if ConnectionPool.shared.connections[relay] != nil {
            ConnectionPool.shared.sendMessage(
                NosturClientMessage(
                    clientMessage: NostrEssentials.ClientMessage(type: .EVENT, event: wrappedEvent),
                    relayType: .WRITE,
                    nEvent: NEvent.fromNostrEssentialsEvent(wrappedEvent)
                ),
                relays: [RelayData(read: false, write: true, search: false, auth: false, url: relay, excludedPubkeys: [])]
            )
        }
        else {
            if let msg = NostrEssentials.ClientMessage(type: .EVENT, event: wrappedEvent).json() {
                Task { @MainActor in
                    ConnectionPool.shared.sendEphemeralMessage(
                        msg,
                        relay: relay,
                        write: true
                    )
                }
            }
        }
    }
}
