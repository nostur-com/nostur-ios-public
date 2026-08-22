//
//  NIP29Models.swift
//  Nostur
//

import Foundation

enum NIP29Kind {
    static let chatMessage = 9

    static let putUser = 9000
    static let removeUser = 9001
    static let editMetadata = 9002
    static let deleteEvent = 9005
    static let createGroup = 9007
    static let deleteGroup = 9008
    static let createInvite = 9009

    static let joinRequest = 9021
    static let leaveRequest = 9022

    static let groupMetadata = 39000
    static let groupAdmins = 39001
    static let groupMembers = 39002
    static let groupRoles = 39003

    static let rememberedGroups = 10009

    static let relayGeneratedKinds: Set<Int> = [
        groupMetadata, groupAdmins, groupMembers, groupRoles
    ]

    static let managementRange = 9000...9022
}

struct NIP29GroupAddress: Hashable, Identifiable, Codable, Sendable {
    let relayURL: String
    let groupId: String

    var id: String { "\(relayURL)|\(groupId)" }

    init(relayURL: String, groupId: String) {
        self.relayURL = normalizeRelayUrl(relayURL)
        self.groupId = groupId
    }
}

struct NIP29SessionKey: Hashable, Codable, Sendable {
    let relayURL: String
    let accountPubkey: String

    init(relayURL: String, accountPubkey: String) {
        self.relayURL = normalizeRelayUrl(relayURL)
        self.accountPubkey = accountPubkey.lowercased()
    }
}

enum NIP29ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

struct NIP29GroupMetadata: Equatable, Sendable {
    var name: String?
    var about: String?
    var pictureURL: String?
    var bannerURL: String?
    var isPrivate = false
    var isRestricted = false
    var isHidden = false
    var isClosed = false
    var supportsLiveKit = false
    var supportedKinds: Set<Int>?

    init(event: NEvent) {
        for tag in event.tags {
            guard let name = tag.tag.first else { continue }
            let value = tag.tag[safe: 1]
            switch name {
            case "name": self.name = value
            case "about": self.about = value
            case "picture": self.pictureURL = value
            case "banner": self.bannerURL = value
            case "private": self.isPrivate = true
            case "restricted": self.isRestricted = true
            case "hidden": self.isHidden = true
            case "closed": self.isClosed = true
            case "livekit": self.supportsLiveKit = true
            case "supported_kinds":
                self.supportedKinds = Set(tag.tag.dropFirst().compactMap(Int.init))
            default: break
            }
        }
    }
}

struct NIP29Member: Identifiable, Equatable, Sendable {
    let pubkey: String
    var roles: [String]

    var id: String { pubkey }
}

struct NIP29EventSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let pubkey: String
    let createdAt: Int
    let kind: Int
    let content: String
    let tags: [[String]]

    init(event: NEvent) {
        self.id = event.id
        self.pubkey = event.publicKey
        self.createdAt = event.createdAt.timestamp
        self.kind = event.kind.id
        self.content = event.content
        self.tags = event.tags.map(\.tag)
    }
}

struct NIP29GroupSnapshot: Identifiable, Equatable, Sendable {
    let id: NIP29GroupAddress
    var connectionState: NIP29ConnectionState = .disconnected
    var metadata: NIP29GroupMetadata?
    var members: [NIP29Member] = []
    var admins: [NIP29Member] = []
    var timeline: [NIP29EventSnapshot] = []
    var isMember = false
    var hasLoadedInitialPage = false
    var lastError: String?
}

enum NIP29Error: LocalizedError, Equatable {
    case invalidRelayURL
    case emptyGroupId
    case accountUnavailable
    case accountCannotSign
    case eventDoesNotBelongToGroup
    case eventPubkeyDoesNotMatchSession
    case invalidRelayFrame
    case relayRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidRelayURL: "Invalid NIP-29 relay URL"
        case .emptyGroupId: "NIP-29 group id cannot be empty"
        case .accountUnavailable: "The account for this group is unavailable"
        case .accountCannotSign: "The account for this group cannot sign events"
        case .eventDoesNotBelongToGroup: "The event does not belong to this group"
        case .eventPubkeyDoesNotMatchSession: "The event was signed by a different account"
        case .invalidRelayFrame: "The relay returned an invalid NIP-29 frame"
        case .relayRejected(let message): message
        }
    }
}
