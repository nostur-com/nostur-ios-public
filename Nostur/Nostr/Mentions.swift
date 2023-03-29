//
//  Mentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import Foundation

// EXAMPLE:
// EROOT
// E1 P1 sometext EROOT E P P P EREPLY

// MY NEW REPLY:
// E2 P2 my_new_EMENTION_text EROOT E EMENTION P P P E1

// 2 STEP PROCESS:
// FIRST: ADD ANY MENTIONS TO THE .TAGS, IN THE CORRECT POSITION, BETWEEN FIRST AND LAST E (FOR NIP-10 COMPATIBILITY)
// SECOND: REPLACE THE MENTIONS WITH THE #[INDEX]

// bumpIndex reserves index #[0] for a Quoted Event to be added later.
// So generated indexes here will be 1 off (+1). but will be correct when the quote event tag is inserted at the first index
func applyMentionsNip08(_ event:NEvent, bumpIndex:Bool = false) -> NEvent {
    let mentionsAsTags = getMentionsAsTags(event.content)
    let orderedTags = nip10OrderedTags(oldTags: event.tags, mentionedTags: mentionsAsTags)
    let newText = replaceTagsWithIndexes(event.content, tags: orderedTags, bumpIndex:bumpIndex)
    var eventWithMentions = event
    eventWithMentions.content = newText
    eventWithMentions.tags = orderedTags
    return eventWithMentions
}


// Returns all mentions as tags
func getMentionsAsTags(_ text:String) -> [NEventTag] {
    
    var mentionsAsTags:[NEventTag] = []
    
    let mentionMatches = text.matchingStrings(regex:#"@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#)
    
    for index in mentionMatches.indices {
        if mentionMatches[index][1] == "note1" {
            if let mention = toHex(String(mentionMatches[index][0].dropFirst(1))) {
                mentionsAsTags.append(NEventTag(type: "e", otherInformation: mention, "", "mention")) // TODO: ADD RELAY HINT
            }
        }
        else if mentionMatches[index][1] == "npub1" {
            if let mention = toHex(String(mentionMatches[index][0].dropFirst(1))) {
                mentionsAsTags.append(NEventTag(type: "p", otherInformation: mention)) // TODO: ADD RELAY HINT
            }
        }
    }
    return mentionsAsTags
}

func toHex(_ bech:String) -> String? {
    guard let nip19 = try? NIP19(displayString: bech) else { return nil }
    return nip19.hexString
}

// Takes original tags, adds or inserts new mentioned tags the correct order (NIP-10)
func nip10OrderedTags(oldTags:[NEventTag], mentionedTags:[NEventTag]) -> [NEventTag] {
    if oldTags.count == 0 {
        return mentionedTags
    }
    var newTags:[NEventTag] = []
    
    // Last "E" should always be the reply to be compatible with old clients
    if (oldTags.filter { $0.type == "e" }.count == 1 && oldTags.filter { $0.type == "e" }.first?.otherInformation[safe: 2] != "mention") {
        // so insert before last e
        newTags = mentionedTags + oldTags
        return newTags
    }
    else if (oldTags.filter { $0.type == "e" }.count >= 2) {
        // insert between
        
        // index of first e tag
        let firstIndex = oldTags.firstIndex { eTag in
            eTag.type == "e"
        }!
        newTags = oldTags
        newTags.insert(contentsOf: mentionedTags, at: (firstIndex + 1))
        return newTags
    }
    else {
        return mentionedTags + oldTags // oldTags has no e's. is only p's?
    }
}

// Takes a text with mentions, and a list of tags, replaces the mentions with the corresponding index in the tags if found.
func replaceTagsWithIndexes(_ text:String, tags:[NEventTag], bumpIndex:Bool) -> String {
    var newText = text
    let urlMatches = text.matchingStrings(regex:#"@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#)
    
    for index in urlMatches.indices {
        let indexInTag = tags.firstIndex { tag in
            if tag.type == "e" {
                if let mention = toHex(String(urlMatches[index][0].dropFirst(1))) {
                    return tag.id == mention
                }
            }
            if tag.type == "p" {
                if let mention = toHex(String(urlMatches[index][0].dropFirst(1))) {
                    return tag.pubkey == mention
                }
            }
            return false
        }
        if (indexInTag != nil) {
            let maybeBumpedIndex = bumpIndex ? indexInTag! + 1 : indexInTag!
            newText = newText.replacingOccurrences(of: String(urlMatches[index][0]), with: "#[\(maybeBumpedIndex)]")
        }
    }
    return newText
}


// Replaces any nsec1... with hunter2
func replaceNsecWithHunter2(_ text:String) -> String {
    var newText = text
    let urlMatches = text.matchingStrings(regex:#"(nsec1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#)
    
    for index in urlMatches.indices {
        if urlMatches[index][1] == "nsec1" {
            newText = newText.replacingOccurrences(of: urlMatches[index][0], with: "hunter2")
        }
    }
    return newText
}

func putHashtagsInTags(_ event:NEvent) -> NEvent {
    let hashtagMatches = event.content.matchingStrings(regex:"#\\w+")
    var eventWithHashtags = event
    for index in hashtagMatches.indices {
        eventWithHashtags
            .tags
            .append(
                NEventTag(type: "t",
                          otherInformation: String(hashtagMatches[index][0].dropFirst())
                         )
            )
    }
    return eventWithHashtags
}
