import CoreData
import Testing
@testable import Nostur

struct BadgeTests {
    private let issuer = String(repeating: "a", count: 64)
    private let recipient = String(repeating: "b", count: 64)
    private let otherRecipient = String(repeating: "c", count: 64)
    private let awardId = String(repeating: "d", count: 64)

    @Test func badgeAddressPreservesColonsInIdentifier() {
        let address = BadgeAddress(value: "30009:\(issuer):conference:2026")
        #expect(address?.issuerPubkey == issuer)
        #expect(address?.identifier == "conference:2026")
        #expect(address?.value == "30009:\(issuer):conference:2026")
    }

    @Test func modernAndLegacyProfilesParseOrderedPairs() {
        let address = "30009:\(issuer):bravery"
        let tags = [
            NostrTag(["a", address]),
            NostrTag(["e", awardId, "wss://relay.example"]),
            NostrTag(["a", "30008:\(issuer):a-badge-set"])
        ]
        let modern = NEvent(publicKey: recipient, kind: .profileBadges, tags: tags)
        let legacy = NEvent(
            publicKey: recipient,
            kind: .badgeSet,
            tags: [NostrTag(["d", "profile_badges"])] + tags
        )

        #expect(badgeReferences(from: modern).map(\.address.value) == [address])
        #expect(badgeReferences(from: legacy).map(\.address.value) == [address])
        #expect(badgeReferences(from: modern).first?.awardRelay == "wss://relay.example")
    }

    @Test func profilePublisherMustActuallyBeAwarded() {
        let address = "30009:\(issuer):bravery"
        let reference = BadgeReference(
            address: BadgeAddress(value: address)!,
            awardEventId: awardId,
            definitionRelay: nil,
            awardRelay: nil
        )
        let definition = NEvent(
            publicKey: issuer,
            kind: .badgeDefinition,
            tags: [NostrTag(["d", "bravery"])]
        )
        let award = NEvent(
            id: awardId,
            publicKey: issuer,
            kind: .badgeAward,
            tags: [NostrTag(["a", address]), NostrTag(["p", otherRecipient])]
        )

        #expect(!isValidBadge(
            reference: reference,
            profilePubkey: recipient,
            award: award,
            definition: definition
        ))
    }

    @Test func validBadgeRequiresMatchingIssuerKindAddressAndRecipient() {
        let address = "30009:\(issuer):bravery"
        let reference = BadgeReference(
            address: BadgeAddress(value: address)!,
            awardEventId: awardId,
            definitionRelay: nil,
            awardRelay: nil
        )
        let definition = NEvent(
            publicKey: issuer,
            kind: .badgeDefinition,
            tags: [NostrTag(["d", "bravery"])]
        )
        let award = NEvent(
            id: awardId,
            publicKey: issuer,
            kind: .badgeAward,
            tags: [NostrTag(["a", address]), NostrTag(["p", recipient])]
        )

        #expect(isValidBadge(
            reference: reference,
            profilePubkey: recipient,
            award: award,
            definition: definition
        ))

        var duplicateAddressAward = award
        duplicateAddressAward.tags.append(NostrTag(["a", address]))
        #expect(!isValidBadge(
            reference: reference,
            profilePubkey: recipient,
            award: duplicateAddressAward,
            definition: definition
        ))
    }

    @Test func publishingUsesModernReplaceableProfileKind() {
        let address = BadgeAddress(value: "30009:\(issuer):bravery")!
        let profile = createProfileBadges(references: [
            BadgeReference(
                address: address,
                awardEventId: awardId,
                definitionRelay: "wss://definitions.example",
                awardRelay: "wss://awards.example"
            )
        ])

        #expect(profile.kind.id == 10008)
        #expect(!profile.tags.contains(where: { $0.type == "d" }))
        #expect(profile.tags.map(\.type) == ["a", "e"])
    }

    @Test func emptyArtworkTagsAreNotPublished() {
        let definition = createBadgeDefinition(
            "bravery",
            name: "Bravery",
            description: "For being brave",
            image1024: "",
            thumb256: ""
        )
        #expect(!definition.tags.contains(where: { $0.type == "image" }))
        #expect(!definition.tags.contains(where: { $0.type == "thumb" }))
    }

    @Test func awardMatchingUsesTagsInsteadOfTheOptionalCoreDataIndex() {
        let address = BadgeAddress(value: "30009:\(issuer):bravery")!
        let award = NEvent(
            id: awardId,
            publicKey: issuer,
            kind: .badgeAward,
            tags: [NostrTag(["a", address.value]), NostrTag(["p", recipient])]
        )

        #expect(award.isBadgeAward(for: address))

        var wrongIssuer = award
        wrongIssuer.publicKey = otherRecipient
        #expect(!wrongIssuer.isBadgeAward(for: address))
    }

    @Test func receivedBadgeCountDeduplicatesAndRejectsSpoofedAwards() {
        let address = "30009:\(issuer):bravery"
        let validAward = NEvent(
            id: awardId,
            publicKey: issuer,
            kind: .badgeAward,
            tags: [NostrTag(["a", address]), NostrTag(["p", recipient])]
        )
        var duplicateAward = validAward
        duplicateAward.id = String(repeating: "e", count: 64)
        var spoofedAward = validAward
        spoofedAward.publicKey = otherRecipient

        let addresses = receivedBadgeAddresses(
            from: [validAward, duplicateAward, spoofedAward],
            recipientPubkey: recipient
        )

        #expect(addresses.map(\.value) == [address])
    }

    @Test func badgeWearersMustReferenceAnAwardForTheProfileOwner() {
        let address = BadgeAddress(value: "30009:\(issuer):bravery")!
        let validAward = NEvent(
            id: awardId,
            publicKey: issuer,
            kind: .badgeAward,
            tags: [NostrTag(["a", address.value]), NostrTag(["p", recipient])]
        )
        let validProfile = NEvent(
            publicKey: recipient,
            kind: .profileBadges,
            tags: [NostrTag(["a", address.value]), NostrTag(["e", awardId])]
        )
        let unawardedProfile = NEvent(
            publicKey: otherRecipient,
            kind: .profileBadges,
            tags: [NostrTag(["a", address.value]), NostrTag(["e", awardId])]
        )

        let wearers = badgeWearerPubkeys(
            for: address,
            profiles: [validProfile, unawardedProfile],
            awardsById: [awardId: validAward]
        )

        #expect(wearers == [recipient])
    }

    @MainActor
    @Test func profileBadgesResolveWithDuplicateFetchedAwardIds() throws {
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        let address = "30009:\(issuer):bravery"
        let profile = NEvent(
            publicKey: recipient,
            kind: .profileBadges,
            tags: [NostrTag(["a", address]), NostrTag(["e", awardId])]
        )
        let award = NEvent(
            id: awardId,
            publicKey: issuer,
            kind: .badgeAward,
            tags: [NostrTag(["a", address]), NostrTag(["p", recipient])]
        )
        let definition = Event.fromNEvent(nEvent: NEvent(
            id: String(repeating: "e", count: 64),
            publicKey: issuer,
            kind: .badgeDefinition,
            tags: [NostrTag(["d", "bravery"])]
        ), context: context)
        _ = Event.fromNEvent(nEvent: award, context: context)
        _ = Event.fromNEvent(nEvent: award, context: context)
        // Fetches include pending inserts, even before the ID constraint is merged on save.

        let request = Event.fetchRequest()
        request.predicate = NSPredicate(format: "kind == %d AND id == %@", BadgeKinds.award, awardId)
        let awards = try context.fetch(request)
        #expect(awards.count == 2)
        #expect(awards[0].objectID != awards[1].objectID)

        let references = badgeReferences(from: profile)
        let resolved = resolveProfileBadges(
            references: references, profilePubkey: recipient,
            awards: awards, definitions: [definition]
        )
        #expect(resolved.count == 1)
        #expect(resolved.first?.reference == references.first)
        #expect(resolved.first?.badge === definition)
        #expect(resolved.first?.badgeAward === awards.first)
        #expect(resolveProfileBadges(
            references: references, profilePubkey: otherRecipient,
            awards: awards, definitions: [definition]
        ).isEmpty)
        #expect(resolveProfileBadges(
            references: references, profilePubkey: recipient,
            awards: awards, definitions: []
        ).isEmpty)
    }
}
