//
//  NXRelayMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/07/2023.
//

import Foundation

// Messages received from relay EVENT/EOSE/NOTICE
struct NXRelayMessage {
    
    var relays: String // space separated relays
    var type: NXRelayMessageType?
    var message: String
    var subscriptionId: String?
    var event: NEvent?
    
    var id: String?
    var success: Bool?
    
    init(relays: String, type: NXRelayMessageType? = nil, message: String, subscriptionId: String? = nil,
         id: String? = nil, success: Bool? = nil, event: NEvent? = nil) {
        self.relays = relays
        self.type = type
        self.message = message
        self.subscriptionId = subscriptionId
        self.event = event
        
        self.id = id
        self.success = success
    }
    
    mutating func setRelays(_ relays: String) {
        self.relays = relays
    }
}

enum NXRelayMessageType: String {
    case EVENT
    case NOTICE
    case EOSE
    case OK
    case AUTH
    case CLOSED
}

enum NXRelayMessageError: Error {
    case FAILED_TO_PARSE // Failed to parse raw websocket
    case UNKNOWN_MESSAGE_TYPE // NOT EVENT, NOTICE or EOSE
    case FAILED_TO_PARSE_EVENT // Could parse raw websocket but not event
    case DUPLICATE_ID // We already received this message (in cache, not db, db check is later)
    case NOT_IN_WOT // Message not in Web of Trust, we don't want it
    case MISSING_EVENT
    case INVALID_SIGNATURE
    case DUPLICATE_ALREADY_SAVED
    case DUPLICATE_ALREADY_PARSED
    case DUPLICATE_ALREADY_RECEIVED
    case DUPLICATE_UNKNOWN
}

private let nxJSONDecoder: JSONDecoder = {
    let d = JSONDecoder()
    return d
}()

@inline(__always)
private func matchesPrefix(_ utf8: String.UTF8View, _ prefix: StaticString) -> Bool {
    prefix.withUTF8Buffer { buffer in
        if utf8.count < buffer.count { return false }

        var index = utf8.startIndex
        for b in buffer {
            if utf8[index] != b { return false }
            index = utf8.index(after: index)
        }
        return true
    }
}

func nxParseRelayMessage(text: String, relay: String) throws -> NXRelayMessage {
    // cheap validate: messages should start with '['
    let utf8 = text.utf8
    guard let first = utf8.first, first == UInt8(ascii: "[") else {
        throw NXRelayMessageError.FAILED_TO_PARSE
    }
    
    guard let dataFromString = text.data(using: .utf8, allowLossyConversion: false) else {
        throw NXRelayMessageError.FAILED_TO_PARSE
    }

    let d = nxJSONDecoder

    if matchesPrefix(utf8, "[\"EOSE\"") {
        guard let eose = try? d.decode(NMessage.self, from: dataFromString) else {
            throw NXRelayMessageError.FAILED_TO_PARSE
        }
        return NXRelayMessage(relays: relay, type: .EOSE, message: text, subscriptionId: eose.subscription)
    }

    if matchesPrefix(utf8, "[\"AUTH\"") {
        return NXRelayMessage(relays: relay, type: .AUTH, message: text)
    }

    if matchesPrefix(utf8, "[\"NOTICE\"") {
        guard let notice = try? d.decode(NMessage.self, from: dataFromString) else {
            throw NXRelayMessageError.FAILED_TO_PARSE
        }
        // same format as eose, but the subscription field contains the notice text per your comment
        return NXRelayMessage(relays: relay, type: .NOTICE, message: notice.subscription)
    }

    if matchesPrefix(utf8, "[\"OK\"") {
        guard let result = try? d.decode(CommandResult.self, from: dataFromString) else {
            throw NXRelayMessageError.FAILED_TO_PARSE
        }
        if result.success {
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(
                id: result.id,
                detectedRelay: relay
            ))
        }
        return NXRelayMessage(relays: relay, type: .OK, message: result.message ?? "", id: result.id, success: result.success)
    }

    if matchesPrefix(utf8, "[\"CLOSED\"") {
        guard let result = try? d.decode(ClosedMessage.self, from: dataFromString) else {
            throw NXRelayMessageError.FAILED_TO_PARSE
        }
        return NXRelayMessage(relays: relay, type: .CLOSED, message: result.message ?? "", id: result.id)
    }

    guard matchesPrefix(utf8, "[\"EVENT\"") else {
        throw NXRelayMessageError.UNKNOWN_MESSAGE_TYPE
    }

    // Try the cheap minimal decode first (duplicate detection)
    if let mMessage = try? d.decode(MinimalMessage.self, from: dataFromString) {
        // These subscriptions: "Following-", "CATCHUP-", "RESUME-", "PAGE-"
        // also can include hashtags, if WoT spam filter is enabled we filter these messages out
        if WOT_FILTER_ENABLED() && subCanHaveHashtags(mMessage.subscriptionId) {
            if !(WebOfTrust.shared.isAllowed(mMessage.pubkey)) {
                throw NXRelayMessageError.NOT_IN_WOT
            }
        }

        updateConnectionStats(receivedPubkey: mMessage.pubkey, fromRelay: relay)

        if let eventState = Importer.shared.existingIds[mMessage.id] {

            if eventState.status == .SAVED {
                let bgContext = bg()
                if mMessage.subscriptionId.hasPrefix("prio-") {
                    if let savedEvent = Event.fetchEvent(id: mMessage.id, isWrapId: mMessage.kind == 1059, context: bgContext) {
                        Importer.shared.importedPrioMessagesFromSubscriptionId.send(
                            ImportedPrioNotification(subscriptionId: mMessage.subscriptionId, event: savedEvent)
                        )
                    }
                }

                let (success, _) = Importer.shared.callbackSubscriptionIds.insert(mMessage.subscriptionId)
                if success {
                    Importer.shared.sendReceivedNotification.send()
                }

                // update from which relays an event id was received, or relay feeds won't work.
                if let relays = eventState.relays, !relays.contains(relay) {
                    updateEventCache(mMessage.id, status: .SAVED, relays: relay)
                    Event.updateRelays(mMessage.id, relays: relay, isWrapId: mMessage.kind == 1059, context: bgContext)
                }
            }

            if eventState.status == .PARSED {
                var sameMessageInQueue = MessageParser.shared.messageBucket.first(where: {
                    mMessage.id == $0.event?.id && $0.type == .EVENT
                })

                if let relays = sameMessageInQueue?.relays {
                    sameMessageInQueue?.setRelays(relays + " " + relay)
                    updateEventCache(mMessage.id, status: .PARSED, relays: sameMessageInQueue?.relays)
                }
            }

            // We should always notify if we received a contact list this session, to enable Follow button
            if mMessage.pubkey == AccountsState.shared.activeAccountPublicKey && mMessage.kind == 3 {
                DispatchQueue.main.async {
                    FollowingGuardian.shared.didReceiveContactListThisSession = true
    #if DEBUG
                    L.og.info("🙂🙂 FollowingGuardian.didReceiveContactListThisSession")
    #endif
                }
            }

            if eventState.status == .SAVED  {
                throw NXRelayMessageError.DUPLICATE_ALREADY_SAVED
            } else if eventState.status == .PARSED {
                throw NXRelayMessageError.DUPLICATE_ALREADY_PARSED
            } else if eventState.status == .RECEIVED && mMessage.kind != 24133 {
                throw NXRelayMessageError.DUPLICATE_ALREADY_RECEIVED
            }
            throw NXRelayMessageError.DUPLICATE_UNKNOWN
        } else {
            updateEventCache(mMessage.id, status: .RECEIVED, relays: relay)
        }
    }
    
    guard var relayMessage = try? d.decode(NMessage.self, from: dataFromString) else {
        throw NXRelayMessageError.FAILED_TO_PARSE
    }

    guard let nEvent = relayMessage.event else {
        throw NXRelayMessageError.MISSING_EVENT
    }

    return NXRelayMessage(relays: relay, type: .EVENT, message: text, subscriptionId: relayMessage.subscription, event: nEvent)
}

struct MinimalMessage: Decodable {
    var container: UnkeyedDecodingContainer
    
    let subscriptionId: String
    let id: String
    let kind: Int
    let pubkey: String
    var relays: String = ""

    init(from decoder: Decoder) throws {
        container = try decoder.unkeyedContainer()
        _ = try container.decode(String.self) // Discard "EVENT"
        subscriptionId = try container.decode(String.self) // for handling callbacks
        let minimalevent = try container.decode(MinimalEvent.self)
        id = minimalevent.id
        kind = minimalevent.kind
        pubkey = minimalevent.pubkey
    }
}

// Instead of full NEvent, this is a minimal one to reduce parsing of duplicate events
// We need:
// - id to check duplicates
// - kind + pubkey to know if we received our contact list this session
struct MinimalEvent: Decodable {
    let id: String
    let kind: Int
    let pubkey: String
}

// These subscriptions: "Following", "CATCHUP-", "RESUME-", "PAGE-"
// also can include hashtags, if WoT spam filter is enabled we filter these messages out
func subCanHaveHashtags(_ subscriptionId: String) -> Bool {
    if subscriptionId.hasPrefix("Following") { return true }
    if subscriptionId.hasPrefix("CATCHUP-") { return true }
    if subscriptionId.hasPrefix("RESUME-") { return true }
    if subscriptionId.hasPrefix("PAGE-") { return true }
    return false
}
