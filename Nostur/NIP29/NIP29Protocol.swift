//
//  NIP29Protocol.swift
//  Nostur
//

import Foundation

enum NIP29Protocol {
    static func subscriptionMessage(
        address: NIP29GroupAddress,
        subscriptionId: String,
        limit: Int = 200
    ) -> String {
        let filters: [[String: Any]] = [
            ["#h": [address.groupId], "limit": limit],
            ["#d": [address.groupId], "kinds": Array(NIP29Kind.relayGeneratedKinds).sorted()]
        ]
        var values: [Any] = [subscriptionId]
        values.append(contentsOf: filters)
        return relayCommand(name: "REQ", values: values)
    }

    static func closeMessage(subscriptionId: String) -> String {
        relayCommand(name: "CLOSE", values: [subscriptionId])
    }

    static func eventMessage(_ event: NEvent) -> String {
        ClientMessage.event(event: event)
    }

    static func authMessage(_ event: NEvent) -> String {
        ClientMessage.auth(event: event)
    }

    static func chatEvent(
        content: String,
        address: NIP29GroupAddress,
        previousEventIds: [String] = []
    ) -> NEvent {
        userEvent(
            kind: NIP29Kind.chatMessage,
            content: content,
            address: address,
            additionalTags: previousTags(from: previousEventIds)
        )
    }

    static func joinRequest(
        address: NIP29GroupAddress,
        inviteCode: String? = nil,
        reason: String = ""
    ) -> NEvent {
        var tags: [NostrTag] = []
        if let inviteCode, !inviteCode.isEmpty {
            tags.append(NostrTag(["code", inviteCode]))
        }
        return userEvent(
            kind: NIP29Kind.joinRequest,
            content: reason,
            address: address,
            additionalTags: tags
        )
    }

    static func leaveRequest(address: NIP29GroupAddress, reason: String = "") -> NEvent {
        userEvent(kind: NIP29Kind.leaveRequest, content: reason, address: address)
    }

    static func rememberedGroupsEvent(groups: [NIP29GroupAddress]) -> NEvent {
        let tags = groups.map { NostrTag(["group", $0.groupId, $0.relayURL]) }
        return NEvent(content: "", kind: .custom(NIP29Kind.rememberedGroups), tags: tags)
    }

    static func groupId(in event: NEvent) -> String? {
        event.tags.first(where: { $0.type == "h" })?.tag[safe: 1]
    }

    static func metadataGroupId(in event: NEvent) -> String? {
        event.tags.first(where: { $0.type == "d" })?.tag[safe: 1]
    }

    static func member(from tag: NostrTag) -> NIP29Member? {
        guard tag.type == "p", let pubkey = tag.tag[safe: 1], pubkey.count == 64 else { return nil }
        return NIP29Member(pubkey: pubkey, roles: Array(tag.tag.dropFirst(2)))
    }

    static func previousTags(from eventIds: [String]) -> [NostrTag] {
        eventIds
            .suffix(3)
            .filter { $0.count >= 8 }
            .map { NostrTag(["previous", String($0.prefix(8))]) }
    }

    private static func userEvent(
        kind: Int,
        content: String,
        address: NIP29GroupAddress,
        additionalTags: [NostrTag] = []
    ) -> NEvent {
        NEvent(
            content: content,
            kind: .custom(kind),
            tags: [NostrTag(["h", address.groupId])] + additionalTags
        )
    }

    private static func relayCommand(name: String, values: [Any]) -> String {
        var command: [Any] = [name]
        command.append(contentsOf: values)
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let string = String(data: data, encoding: .utf8)
        else { return "" }
        return string
    }
}

enum NIP29RelayFrame {
    case auth(challenge: String)
    case event(subscriptionId: String, event: NEvent)
    case eose(subscriptionId: String)
    case ok(eventId: String, accepted: Bool, message: String)
    case closed(subscriptionId: String, message: String)
    case notice(String)

    static func parse(_ text: String) throws -> NIP29RelayFrame {
        guard let data = text.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              let command = array.first as? String
        else { throw NIP29Error.invalidRelayFrame }

        switch command {
        case "AUTH":
            guard let challenge = array[safe: 1] as? String else { throw NIP29Error.invalidRelayFrame }
            return .auth(challenge: challenge)
        case "EVENT":
            guard let subscriptionId = array[safe: 1] as? String,
                  let object = array[safe: 2],
                  JSONSerialization.isValidJSONObject(object)
            else { throw NIP29Error.invalidRelayFrame }
            let eventData = try JSONSerialization.data(withJSONObject: object)
            return .event(subscriptionId: subscriptionId, event: try JSONDecoder().decode(NEvent.self, from: eventData))
        case "EOSE":
            guard let subscriptionId = array[safe: 1] as? String else { throw NIP29Error.invalidRelayFrame }
            return .eose(subscriptionId: subscriptionId)
        case "OK":
            guard let eventId = array[safe: 1] as? String,
                  let accepted = array[safe: 2] as? Bool
            else { throw NIP29Error.invalidRelayFrame }
            return .ok(eventId: eventId, accepted: accepted, message: array[safe: 3] as? String ?? "")
        case "CLOSED":
            guard let subscriptionId = array[safe: 1] as? String else { throw NIP29Error.invalidRelayFrame }
            return .closed(subscriptionId: subscriptionId, message: array[safe: 2] as? String ?? "")
        case "NOTICE":
            return .notice(array[safe: 1] as? String ?? "")
        default:
            throw NIP29Error.invalidRelayFrame
        }
    }
}
