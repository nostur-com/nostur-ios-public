//
//  Badges.swift
//  Nostur
//
//  NIP-58 domain model, validation and relay loading.
//

import Foundation
import CoreData
import NostrEssentials

enum BadgeKinds {
    static let award = 8
    static let profile = 10008
    static let legacyProfile = 30008
    static let definition = 30009
    static let legacyProfileIdentifier = "profile_badges"
}

struct BadgeAddress: Hashable, Identifiable {
    let issuerPubkey: String
    let identifier: String

    var id: String { value }
    var value: String { "\(BadgeKinds.definition):\(issuerPubkey):\(identifier)" }

    init?(value: String) {
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == Substring(String(BadgeKinds.definition)),
              Self.isHex64(String(parts[1])),
              !parts[2].isEmpty else { return nil }
        issuerPubkey = String(parts[1])
        identifier = String(parts[2])
    }

    init?(definition: NEvent) {
        guard definition.kind.id == BadgeKinds.definition,
              Self.isHex64(definition.publicKey),
              let identifier = definition.tags.first(where: { $0.type == "d" })?.value,
              !identifier.isEmpty else { return nil }
        issuerPubkey = definition.publicKey
        self.identifier = identifier
    }

    private static func isHex64(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}

struct BadgeReference: Hashable, Identifiable {
    let address: BadgeAddress
    let awardEventId: String
    let definitionRelay: String?
    let awardRelay: String?

    var id: String { "\(address.value)|\(awardEventId)" }
}

struct ProfileBadge: Identifiable {
    var id: String { reference.id }
    let reference: BadgeReference
    let badge: Event
    let badgeAward: Event
}

func badgeReferences(from profile: NEvent) -> [BadgeReference] {
    let isModern = profile.kind.id == BadgeKinds.profile
    let isLegacy = profile.kind.id == BadgeKinds.legacyProfile
        && profile.tags.contains(where: { $0.type == "d" && $0.value == BadgeKinds.legacyProfileIdentifier })
    guard isModern || isLegacy else { return [] }

    var references: [BadgeReference] = []
    var index = 0
    while index + 1 < profile.tags.count {
        let addressTag = profile.tags[index]
        let awardTag = profile.tags[index + 1]
        guard addressTag.type == "a",
              awardTag.type == "e",
              let address = BadgeAddress(value: addressTag.value),
              awardTag.value.count == 64 else {
            index += 1
            continue
        }
        references.append(BadgeReference(
            address: address,
            awardEventId: awardTag.value,
            definitionRelay: addressTag.tag[safe: 2],
            awardRelay: awardTag.tag[safe: 2]
        ))
        index += 2
    }
    return references
}

func isValidBadge(
    reference: BadgeReference,
    profilePubkey: String,
    award: NEvent,
    definition: NEvent
) -> Bool {
    guard award.id == reference.awardEventId,
          award.isBadgeAward(for: reference.address),
          definition.kind.id == BadgeKinds.definition,
          definition.publicKey == reference.address.issuerPubkey,
          BadgeAddress(definition: definition) == reference.address else { return false }

    return award.tags.contains { $0.type == "p" && $0.value == profilePubkey }
}

func receivedBadgeAddresses(from awards: [NEvent], recipientPubkey: String) -> Set<BadgeAddress> {
    Set(awards.compactMap { award in
        let addressTags = award.tags.filter { $0.type == "a" }
        guard award.kind.id == BadgeKinds.award,
              addressTags.count == 1,
              award.tags.contains(where: { $0.type == "p" && $0.value == recipientPubkey }),
              let address = BadgeAddress(value: addressTags[0].value),
              award.publicKey == address.issuerPubkey else { return nil }
        return address
    })
}

func badgeWearerPubkeys(
    for address: BadgeAddress,
    profiles: [NEvent],
    awardsById: [String: NEvent]
) -> Set<String> {
    badgeWearersByAddress(
        addresses: [address],
        profiles: profiles,
        awardsById: awardsById
    )[address] ?? []
}

func badgeWearersByAddress(
    addresses: Set<BadgeAddress>,
    profiles: [NEvent],
    awardsById: [String: NEvent]
) -> [BadgeAddress: Set<String>] {
    var wearersByAddress: [BadgeAddress: Set<String>] = [:]
    for profile in profiles {
        for reference in badgeReferences(from: profile) where addresses.contains(reference.address) {
            guard let award = awardsById[reference.awardEventId],
                  award.id == reference.awardEventId,
                  award.isBadgeAward(for: reference.address),
                  award.tags.contains(where: { $0.type == "p" && $0.value == profile.publicKey }) else { continue }
            wearersByAddress[reference.address, default: []].insert(profile.publicKey)
        }
    }
    return wearersByAddress
}

func createBadgeDefinition(
    _ code: String,
    name: String,
    description: String,
    image1024: String,
    thumb256: String
) -> NEvent {
    var badge = NEvent(content: "")
    badge.kind = .badgeDefinition
    badge.tags.append(NostrTag(["d", code.trimmingCharacters(in: .whitespacesAndNewlines)]))
    if !name.isEmpty { badge.tags.append(NostrTag(["name", name])) }
    if !description.isEmpty { badge.tags.append(NostrTag(["description", description])) }
    if !image1024.isEmpty { badge.tags.append(NostrTag(["image", image1024, "1024x1024"])) }
    if !thumb256.isEmpty { badge.tags.append(NostrTag(["thumb", thumb256, "256x256"])) }
    return badge
}

func createBadgeAward(definitionAddress: String, pubkeys: [String]) -> NEvent? {
    guard BadgeAddress(value: definitionAddress) != nil else { return nil }
    let recipients = Array(Set(pubkeys.filter { $0.count == 64 })).sorted()
    guard !recipients.isEmpty else { return nil }

    var award = NEvent(content: "")
    award.kind = .badgeAward
    award.tags.append(NostrTag(["a", definitionAddress]))
    award.tags.append(contentsOf: recipients.map { NostrTag(["p", $0]) })
    return award
}

func createProfileBadges(references: [BadgeReference]) -> NEvent {
    var profile = NEvent(content: "")
    profile.kind = .profileBadges
    var seen = Set<String>()
    for reference in references where seen.insert(reference.address.value).inserted {
        var addressTag = ["a", reference.address.value]
        if let relay = reference.definitionRelay, !relay.isEmpty { addressTag.append(relay) }
        var awardTag = ["e", reference.awardEventId]
        if let relay = reference.awardRelay, !relay.isEmpty { awardTag.append(relay) }
        profile.tags.append(NostrTag(addressTag))
        profile.tags.append(NostrTag(awardTag))
    }
    return profile
}

extension NEvent {
    var badgeCode: NostrTag? { tags.first(where: { $0.type == "d" }) }
    var badgeName: NostrTag? { tags.first(where: { $0.type == "name" }) }
    var badgeDescription: NostrTag? { tags.first(where: { $0.type == "description" }) }
    var badgeImage: NostrTag? { tags.first(where: { $0.type == "image" }) }
    var badgeThumbs: [NostrTag] { tags.filter { $0.type == "thumb" } }
    var badgeThumb: NostrTag? { badgeThumbs.first }
    var badgeAddress: BadgeAddress? { BadgeAddress(definition: self) }
    var badgeA: String? { badgeAddress?.value }
    var badgeAtag: NostrTag? { tags.first(where: { $0.type == "a" }) }

    func isBadgeAward(for address: BadgeAddress) -> Bool {
        let addressTags = tags.filter { $0.type == "a" }
        return kind.id == BadgeKinds.award
            && publicKey == address.issuerPubkey
            && addressTags.count == 1
            && addressTags[0].value == address.value
    }
}

extension Event {
    var badgeAddress: BadgeAddress? { BadgeAddress(definition: toNEvent()) }
    var badgeA: String? { badgeAddress?.value }

    func isBadgeAward(for address: BadgeAddress) -> Bool {
        toNEvent().isBadgeAward(for: address)
    }

    var badgeAwards: [Event] {
        guard let context = managedObjectContext, let badgeAddress else { return [] }
        let request = Event.fetchRequest()
        request.predicate = NSPredicate(
            format: "kind == %d AND pubkey == %@",
            BadgeKinds.award,
            pubkey
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        return ((try? context.fetch(request)) ?? []).filter { $0.isBadgeAward(for: badgeAddress) }
    }

    var awardedTo: [NostrTag] {
        let uniquePubkeys = Set(badgeAwards.flatMap { $0.pTags() })
        return uniquePubkeys.sorted().map { NostrTag(["p", $0]) }
    }

    var badgeDefinition: Event? {
        guard let context = managedObjectContext,
              kind == Int64(BadgeKinds.award),
              let addressValue = firstA(),
              let address = BadgeAddress(value: addressValue),
              pubkey == address.issuerPubkey else { return nil }
        return Event.fetchReplacableEvent(
            Int64(BadgeKinds.definition),
            pubkey: address.issuerPubkey,
            definition: address.identifier,
            context: context
        )
    }

    var verifiedBadges: [ProfileBadge] {
        guard let context = managedObjectContext else { return [] }
        return badgeReferences(from: toNEvent()).compactMap { reference in
            guard let award = Event.fetchEvent(id: reference.awardEventId, context: context),
                  let definition = Event.fetchReplacableEvent(
                    Int64(BadgeKinds.definition),
                    pubkey: reference.address.issuerPubkey,
                    definition: reference.address.identifier,
                    context: context
                  ),
                  isValidBadge(
                    reference: reference,
                    profilePubkey: pubkey,
                    award: award.toNEvent(),
                    definition: definition.toNEvent()
                  ) else { return nil }
            return ProfileBadge(reference: reference, badge: definition, badgeAward: award)
        }
    }
}

enum BadgeRelayLoader {
    static func fetchProfile(pubkey: String) async {
        _ = try? await relayReq(
            Filters(authors: [pubkey], kinds: [BadgeKinds.profile, BadgeKinds.legacyProfile], limit: 10),
            timeout: 4.5,
            accountPubkey: pubkey,
            useOutbox: true
        )
    }

    static func fetchReceived(pubkey: String) async {
        _ = try? await relayReq(
            Filters(kinds: [BadgeKinds.award], tagFilter: TagFilter(tag: "p", values: [pubkey]), limit: 500),
            timeout: 5.5,
            accountPubkey: pubkey
        )
    }

    static func fetchIssued(pubkey: String) async {
        _ = try? await relayReq(
            Filters(authors: [pubkey], kinds: [BadgeKinds.definition, BadgeKinds.award], limit: 500),
            timeout: 5.5,
            accountPubkey: pubkey,
            useOutbox: true
        )
    }

    static func fetchAwards(for address: BadgeAddress, accountPubkey: String? = nil) async {
        _ = try? await relayReq(
            Filters(
                authors: [address.issuerPubkey],
                kinds: [BadgeKinds.award],
                tagFilter: TagFilter(tag: "a", values: [address.value]),
                limit: 500
            ),
            timeout: 5.5,
            accountPubkey: accountPubkey,
            useOutbox: true
        )
    }

    static func fetchDefinition(for address: BadgeAddress, accountPubkey: String? = nil) async {
        _ = try? await relayReq(
            Filters(
                authors: [address.issuerPubkey],
                kinds: [BadgeKinds.definition],
                tagFilter: TagFilter(tag: "d", values: [address.identifier]),
                limit: 1
            ),
            timeout: 4.5,
            accountPubkey: accountPubkey,
            useOutbox: true
        )
    }

    static func fetchWearers(for addresses: Set<BadgeAddress>, accountPubkey: String? = nil) async {
        guard !addresses.isEmpty else { return }
        _ = try? await relayReq(
            Filters(
                kinds: [BadgeKinds.profile, BadgeKinds.legacyProfile],
                tagFilter: TagFilter(tag: "a", values: Set(addresses.map(\.value))),
                limit: 500
            ),
            timeout: 5.5,
            accountPubkey: accountPubkey
        )
    }

    static func fetchDependencies(for references: [BadgeReference], accountPubkey: String? = nil) async {
        let awardIds = Set(references.map(\.awardEventId))
        if !awardIds.isEmpty {
            _ = try? await relayReq(Filters(ids: awardIds), timeout: 4.5, accountPubkey: accountPubkey)
        }

        let definitionsByIssuer = Dictionary(grouping: references.map(\.address), by: \.issuerPubkey)
        for (issuer, addresses) in definitionsByIssuer {
            _ = try? await relayReq(
                Filters(
                    authors: [issuer],
                    kinds: [BadgeKinds.definition],
                    tagFilter: TagFilter(tag: "d", values: Set(addresses.map(\.identifier)))
                ),
                timeout: 4.5,
                accountPubkey: accountPubkey,
                useOutbox: true
            )
        }
    }
}

actor BadgeRefreshCoordinator {
    static let shared = BadgeRefreshCoordinator()

    private let startupDelayNanoseconds: UInt64 = 10_000_000_000
    private let receivedRefreshInterval: TimeInterval = 15 * 60
    private let profileRefreshInterval: TimeInterval = 5 * 60
    private var activeRefreshes = Set<String>()
    private var lastProfileRefresh: [String: Date] = [:]

    func refreshReceivedAfterDelay(pubkey: String) async {
        do {
            try await Task.sleep(nanoseconds: startupDelayNanoseconds)
        } catch {
            return
        }
        await refreshReceived(pubkey: pubkey, force: false)
    }

    func refreshReceived(pubkey: String, force: Bool) async {
        let operationKey = "received:\(pubkey)"
        guard !activeRefreshes.contains(operationKey) else { return }

        let defaultsKey = accountSpecificKey(pubkey, forKey: "last_badge_awards_refresh_timestamp")
        if !force {
            let lastRefresh = UserDefaults.standard.double(forKey: defaultsKey)
            guard Date.now.timeIntervalSince1970 - lastRefresh >= receivedRefreshInterval else { return }
        }

        activeRefreshes.insert(operationKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: defaultsKey)
        await BadgeRelayLoader.fetchReceived(pubkey: pubkey)
        activeRefreshes.remove(operationKey)
    }

    func refreshProfile(pubkey: String) async {
        let operationKey = "profile:\(pubkey)"
        guard !activeRefreshes.contains(operationKey) else { return }
        if let lastRefresh = lastProfileRefresh[pubkey],
           Date.now.timeIntervalSince(lastRefresh) < profileRefreshInterval { return }

        activeRefreshes.insert(operationKey)
        lastProfileRefresh[pubkey] = .now
        await BadgeRelayLoader.fetchProfile(pubkey: pubkey)
        activeRefreshes.remove(operationKey)
    }
}
