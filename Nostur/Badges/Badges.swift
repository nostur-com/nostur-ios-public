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
