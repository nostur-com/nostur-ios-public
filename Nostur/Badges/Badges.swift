//
//  Badges.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

// TODO: NIP-58: Badge definitions can be updated.

import Foundation

// createBadgeDefinition("nostur_og", name:"Nostur OG", description: "Early adoptor of Nostur", image1024:"", thumb50:"")
func createBadgeDefinition(_ code:String, name:String, description:String, image1024:String, thumb256:String) -> NEvent {
    var badgeDef = NEvent(content: "")
    badgeDef.kind = .badgeDefinition
    badgeDef.tags.append(NEventTag(type: "d", otherInformation: code))
    badgeDef.tags.append(NEventTag(type: "name", otherInformation: name))
    badgeDef.tags.append(NEventTag(type: "description", otherInformation: description))
    badgeDef.tags.append(NEventTag(type: "image", otherInformation: image1024, "1024x1024"))
    badgeDef.tags.append(NEventTag(type: "thumb", otherInformation: thumb256, "256x256"))
    return badgeDef
}


// createBadgeAward("nostur_og", pubkeys:pubkeys)
func createBadgeAward(_ pubkey:String, badgeCode:String, pubkeys:[String]) -> NEvent {
    var badgeAward = NEvent(content: "")
    badgeAward.kind = .badgeAward
    badgeAward.tags.append(NEventTag(type: "a", otherInformation: "30009:\(pubkey):\(badgeCode)"))
    for p in pubkeys {
        badgeAward.tags.append(NEventTag.pubKey(publicKey: p))
    }
    return badgeAward
}

// createProfileBadges(awards: awards)
func createProfileBadges(awards:[NEvent]) -> NEvent {
    var profileBadges = NEvent(content: "")
    profileBadges.kind = .profileBadges
    profileBadges.tags.append(NEventTag(type: "d", otherInformation: "profile_badges"))
    var noDuplicateATags:Set<String> = []
    for award in awards {
        if let awardFirstA = award.firstA() {
            guard !noDuplicateATags.contains(awardFirstA) else { continue }
            profileBadges.tags.append(NEventTag(type: "a", otherInformation: awardFirstA ))
            profileBadges.tags.append(NEventTag(type: "e", otherInformation: award.id))
            noDuplicateATags.insert(awardFirstA)
        }
    }
    return profileBadges
}

extension NEvent {
    
    // ON KIND:30009 - BADGE DEFINITION - TAGS/FIELDS
    var badgeCode:NEventTag? {
        tags.first(where: { $0.type == "d" })
    }
    
    var badgeName:NEventTag? {
        tags.first(where: { $0.type == "name" })
    }
    
    var badgeDescription:NEventTag? {
        tags.first(where: { $0.type == "description" })
    }
    
    var badgeImage:NEventTag? {
        tags.first(where: { $0.type == "image" })
    }
    
    var badgeThumb:NEventTag? {
        tags.first(where: { $0.type == "thumb" })
    }
    
    // compiles the badge tags into a badge "a" tag: ["a", "30009:alice:bravery"],
    var badgeA:String { kind == .badgeDefinition ? "\(String(kind.id)):\(publicKey):\(badgeCode?.value ?? "ERROR")" : "ERRORERRORERRORERRORERRORERRORERRORERROR" }
    
    
    // ON KIND:8 - BADGE AWARD - ["a","30009:alice:bravery"],
    var badgeAtag:NEventTag? {
        tags.first(where: { $0.type == "a" })
    }
}

extension NEventTag {
    public var definition: String {
        return underlyingData.suffix(from: 1).first!
    }
}


extension Event {
    
    /**
     {
         "id": "badgedef_11023e6a3fe605677095cb4015f7b8cec576d3f5614ef5a958af07a3b49381eb",
         "pubkey": "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
         "created_at": 1677602715,
         "kind": 30009,
         "tags": [
             ["d","nostur_og"],
             ["name","Nostur OG"],
             ["description","Early user of Nostur"],
             ["image", "", "1024x1024"],
             ["thumb", "", "50x50"]
         ],
         "sig": "cf08316c5af3d42f32024bd93de05226390019088eb9ef88439da3d2389625852c1b5fc80b4f99f4bf5062a67c3771c1f74990b17f98ae60995db80d677617ed"
     }

     */
    
    // BADGE DEFINITION HELPERS - RETURNS ALL KIND:8 FOR THIS KIND:30009
    var badgeAwards:[Event] {
        get {
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "kind == 8 and pubkey == %@", pubkey)
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let awards = (try? managedObjectContext?.fetch(r)) ?? []
            let awardsForThisBadge = awards.filter { award in
                let badgeA = "\(String(kind)):\(pubkey):\(firstD() ?? "ERROR")"
                guard let awardsFirstA = award.firstA() else { return false }
                guard awardsFirstA == badgeA else { return false }
                return true
            }
            return awardsForThisBadge
        }
    }
    
    // compiles the badge tags from KIND 30009 into a badge "a" tag
    var badgeA:String { kind == 30009 ? "\(String(kind)):\(pubkey):\(firstD() ?? "ERROR")" : "ERRORERRORERRORERRORERRORERROR" }
    
    // ALL THE P's this BADGE AWARD is awarding
    var awardedTo:[NEventTag] {
        return badgeAwards.reduce([]) { partialResult, award in
            return partialResult + award.tags().filter { $0.type == "p" }
        }
    }
    
    
    /**
     {
         "id": "badgeaward_11023e6a3fe605677095cb4015f7b8cec576d3f5614ef5a958af07a3b49381eb",
         "pubkey": "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
         "created_at": 1677602715,
         "kind": 8,
         "tags": [
             ["a", "30009:9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e:bravery"],
             ["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]
             ["p","8be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]
         ],
         "sig": "cf08316c5af3d42f32024bd93de05226390019088eb9ef88439da3d2389625852c1b5fc80b4f99f4bf5062a67c3771c1f74990b17f98ae60995db80d677617ed"
     }
     */
    
    // BADGE AWARDS HELPERS
    // BADGE DEFINITION HELPERS
    var badgeDefinition:Event? {
        get {
            guard let aTag = tags().first(where: { $0.type == "a" }) else { return nil }
            let badgeATag = BadgeATag(aTag)
            if let definitionEvent = try? Event.fetchReplacableEvent(badgeATag.kind, pubkey: badgeATag.pubkey, definition: badgeATag.badgeCode, context: managedObjectContext!) {
                return definitionEvent
            }
            return nil
        }
    }
    
}


extension Event {
    
    /**
     {
         "pubkey": "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
         "content": "",
         "id": "da4b67f4789999190498d647b119a27dfc00076219957781dc5c27f08e349ced",
         "created_at": 1677697678,
         "sig": "ff70e7bb7be4070381012cdf9d840672288f0482acf0eae162b0fa6e065a370726b60be76ebc4063cfc3195e9cbbc04a0714afa9e3e83f36b75eab1222294658",
         "kind": 30008,
         "tags": [
             [
                 "d",
                 "profile_badges"
             ],
             [
                 "a",
                 "30009:9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e:bravery"
             ],
             [
                 "e",
                 "51196b78f843c3abfc037b5b375e75900416fb33c328f2df999e883520411916"
             ]
         ]
     }
     */
    
    // PROFILE BADGES HELPERS
    var verifiedBadges:[ProfileBadge] {
        get {
            var badges:[ProfileBadge] = []
            let nTags = tags()
            
            var badgeCollector: (Event?, NEventTag?, Event?) // Tuple of kind 30009, aTag, and kind 8 for readability
            
            // NIP-58: MUST BE PRESENT: A d tag with the unique identifier profile_badges
            if !nTags.contains(where: { nTag in
                nTag.type == "d" && nTag.value == "profile_badges"
            }) { return [] }
            
            for index in nTags.indices {
                if nTags[index].type == "a" { //  ["a", "30009:alice:bravery"],
                    let aTag = BadgeATag(nTags[index])
                    if let definitionEvent = try? Event.fetchReplacableEvent(aTag.kind, pubkey: aTag.pubkey, definition: aTag.badgeCode, context: managedObjectContext!) {
                        badgeCollector = (definitionEvent, nTags[index], nil)
                    }
                    else {
                        badgeCollector = (nil, nil, nil)
                    }
                }
                if nTags[index].type == "e" && badgeCollector.0 != nil { // ["e", "<bravery badge award event id>", "wss://nostr.academy"],
                    if let badgeAwardEvent = try? Event.fetchEvent(id: nTags[index].value, context: managedObjectContext!) {
                        // NIP-58: .Badge Awards referenced by the e tags should contain the same a tag.
                        guard let badgeAwardATag = badgeAwardEvent.firstA(), badgeAwardATag == badgeCollector.1!.value else {
                            badgeCollector = (nil, nil, nil)
                            continue
                        }
                        // Check 30009.pubkey == 8.pubkey?
                        guard badgeAwardEvent.pubkey == badgeCollector.0!.pubkey  else {
                            badgeCollector = (nil, nil, nil)
                            continue
                        }
                        badgeCollector = (badgeCollector.0, badgeCollector.1, badgeAwardEvent)
                        badges.append(ProfileBadge(badge: badgeCollector.0!, badgeAward: badgeCollector.2!))
                        badgeCollector = (nil, nil, nil)
                    }
                    else {
                        badgeCollector = (nil, nil, nil)
                    }
                }
            }

            return badges
            // NIP-58: Clients SHOULD ignore a without corresponding e tag and viceversa. Badge Awards referenced by the e tags should contain the same a tag.
            return badges.compactMap {
                $0.badgeAward.toNEvent().badgeAtag?.value == $0.badge.badgeA ? $0 : nil
            }
        }
    }
}

struct BadgeATag {
    let kind:Int64
    let pubkey:String
    let badgeCode:String
    init(_ a:NEventTag) {
        let elements = a.value.split(separator: ":")
        guard elements.count >= 3 else {
            kind = 30009
            pubkey = "NONE"
            badgeCode = "NONE"
            return
        }
        self.kind = Int64(elements[safe: 0] ?? "30009") ?? 30009
        self.pubkey = String(elements[safe: 1] ?? "ERROR")
        self.badgeCode = String(elements[safe: 2] ?? "ERROR")
    }
    
    init(_ a:String) {
        let elements = a.split(separator: ":")
        guard elements.count >= 3 else {
            kind = 30009
            pubkey = "NONE"
            badgeCode = "NONE"
            return
        }
        self.kind = Int64(elements[safe: 0] ?? "30009") ?? 30009
        self.pubkey = String(elements[safe: 1] ?? "ERROR")
        self.badgeCode = String(elements[safe: 2] ?? "ERROR")
    }
                    
}

struct ProfileBadge:Identifiable {
    var id:String { badgeAward.id } // Not sure, but should be good enough to make unique for ForEach
    var badge:Event // The badge definition
    var badgeAward:Event // The event the badge was awarded in
}
