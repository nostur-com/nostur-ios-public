//
//  Badges.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

// TODO: NIP-58: Badge definitions can be updated.

import Foundation

// createBadgeDefinition("nostur_og", name:"Nostur OG", description: "Early adoptor of Nostur", image1024:"", thumb50:"")
func createBadgeDefinition(_ id:String, name:String, description:String, image1024:String, thumb100:String) -> NEvent {
    var badgeDef = NEvent(content: "")
    badgeDef.kind = .badgeDefinition
    badgeDef.tags.append(NEventTag(type: "d", otherInformation: id))
    badgeDef.tags.append(NEventTag(type: "name", otherInformation: name))
    badgeDef.tags.append(NEventTag(type: "description", otherInformation: description))
    badgeDef.tags.append(NEventTag(type: "image", otherInformation: image1024, "1024x1024"))
    badgeDef.tags.append(NEventTag(type: "thumb", otherInformation: thumb100, "50x50"))
    return badgeDef
}


// createBadgeAward("nostur_og", pubkeys:pubkeys)
func createBadgeAward(badgeDefinitionId:String, pubkeys:[String]) -> NEvent {
    var badgeAward = NEvent(content: "")
    badgeAward.kind = .badgeAward
    badgeAward.tags.append(NEventTag(type: "a", otherInformation: badgeDefinitionId))
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
    for award in awards {
        if let badgeDefinitionTag = award.badgeDefinitionId {
            profileBadges.tags.append(NEventTag(type: "a", otherInformation: badgeDefinitionTag.definition ))
            profileBadges.tags.append(NEventTag(type: "e", otherInformation: award.id))
        }
    }
    return profileBadges
}

extension NEvent {
    
    // BADGE DEFINITION TAGS
    var badgeDefinition:NEventTag? {
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
    
    // BADGE AWARD TAGS
    var badgeDefinitionId:NEventTag? {
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
         "kind": 30008,
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
    
    // BADGE DEFINITION HELPERS
    var badgeAwards:[Event] {
        get {
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "kind == 8 and pubkey == %@", pubkey)
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let awards = (try? managedObjectContext?.fetch(r)) ?? []
            let awardsForThisBadge = awards.filter { award in
                return id == award.toNEvent().badgeDefinitionId?.value
            }
            return awardsForThisBadge
        }
    }
    
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
             ["a","badgedef_11023e6a3fe605677095cb4015f7b8cec576d3f5614ef5a958af07a3b49381eb"]
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
            guard toNEvent().badgeDefinitionId != nil else { return nil }
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "id == %@", toNEvent().badgeDefinitionId!.value)
            return try? managedObjectContext?.fetch(r).first
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
                 "6215b9fee3834ff25da4962dfb0d72e3dd648a454491dc213da5bdf735d7ddd9"
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
            
            var badgeCollector: (Event?, Event?) // Tuple of kind 30009 and kind 8 for readability
            
            // NIP-58: MUST BE PRESENT: A d tag with the unique identifier profile_badges
            if !nTags.contains(where: { nTag in
                nTag.type == "d" && nTag.value == "profile_badges"
            }) { return [] }
            
            for index in nTags.indices {
                if nTags[index].type == "a" { // REFERENCE TO BADGE DEFINITION ID
                    if let definition = try? Event.fetchEvent(id: nTags[index].value, context: managedObjectContext!) {
                        badgeCollector = (definition, nil)
                    }
                    else {
                        badgeCollector = (nil, nil)
                    }
                }
                if nTags[index].type == "e" && badgeCollector.0 != nil { // REFERENCE TO BADGE AWARD ID
                    if let badgeAward = try? Event.fetchEvent(id: nTags[index].value, context: managedObjectContext!) {
                        badgeCollector = (badgeCollector.0, badgeAward)
                        badges.append(ProfileBadge(badge: badgeCollector.0!, badgeAward: badgeCollector.1!))
                        badgeCollector = (nil, nil)
                    }
                    else {
                        badgeCollector = (nil, nil)
                    }
                }
            }

            // NIP-58: Clients SHOULD ignore a without corresponding e tag and viceversa. Badge Awards referenced by the e tags should contain the same a tag.
            return badges.compactMap {
                $0.badgeAward.toNEvent().badgeDefinitionId?.id == $0.badge.id ? $0 : nil
            }
        }
    }
}

struct ProfileBadge:Identifiable {
    var id:String { badgeAward.id } // Not sure, but should be good enough to make unique for ForEach
    var badge:Event // The badge definition
    var badgeAward:Event // The event the badge was awarded in
}
