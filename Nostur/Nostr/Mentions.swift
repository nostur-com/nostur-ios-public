//
//  Mentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import Foundation

func replaceMentionsWithNpubs(_ text:String, selected:[Contact] = []) -> String {
    let blocked:[String] = blocks()
    let mentions = text.matches(of: /(?:^|\s)((@(\x{2063}\x{2064}[^\x{2063}\x{2064}]+\x{2064}\x{2063}|\w+)))/)
    var newText = text
    let mentionsByLongest = mentions.sorted(by: { $0.output.3.count > $1.output.3.count })
    for mention in mentionsByLongest {
//        print("replaceMentionsWithNpubs")
//        print(mention.output.0) // @Tester
//        print(mention.output.1) // @Tester
//        print(mention.output.2) // @Tester
//        print(mention.output.3) // Tester
        let term = mention.output.3.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{2063}", with: "")
            .replacingOccurrences(of: "\u{2064}", with: "")
        let fr = Contact.fetchRequest()
        fr.predicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", term, term, blocked)
        
        // prio selected contacts - exact result
        if let result = selected.first(where: {
            let displayName = ($0.display_name ?? "").lowercased()
            let name = ($0.name ?? "").lowercased()
            
            if displayName == term { return true }
            if name == term { return true }
            return false
        }) {
//            print("selected [exact!] result: \(result.authorName)")
            newText = newText.replacingOccurrences(of: mention.output.2, with: "@\(result.npub)", options: [.caseInsensitive])
            continue
        }
        
        // prio selected contacts - contains result
        else if let result = selected.first(where: {
            let displayName = ($0.display_name ?? "").lowercased()
            let name = ($0.name ?? "").lowercased()
            
            if displayName.contains(term) { return true }
            if name.contains(term) { return true }
            return false
        }) {
//            print("selected [contains!] result: \(result.authorName)")
            newText = newText.replacingOccurrences(of: mention.output.2, with: "@\(result.npub)", options: [.caseInsensitive])
            continue
        }
                
        
        else if let result = try? DataProvider.shared().viewContext.fetch(fr).first {
//            print("any! result \(result.handle) \(result.npub)")
            newText = newText.replacingOccurrences(of: mention.output.2, with: "@\(result.npub)", options: [.caseInsensitive])
        }
    }
    return newText
}

// EXAMPLE:
// EROOT
// E1 P1 sometext EROOT E P P P EREPLY

// MY NEW REPLY:
// E2 P2 my_new_MENTION_text EROOT E EMENTION P P P E1

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
func getMentionsAsTags(_ text:String) -> [NostrTag] {
    var mentionsAsTags:[NostrTag] = []
    let notesAndNpubs = text.matches(of: /@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})/)
//    print(text)
//    print("notesAndNpubs: \(notesAndNpubs.count)")
    for match in notesAndNpubs {
        // print(match.output.0) // @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9
        // print(match.output.1) // npub1
        // print(match.output.2) // sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9
        if match.output.1 == "note1" {
            if let mention = toHex(String(match.output.0.dropFirst(1))) {
                mentionsAsTags.append(NostrTag(["e", mention, "", "mention"])) // TODO: ADD RELAY HINT
            }
        }
        else if match.output.1 == "npub1" {
            if let mention = toHex(String(match.output.0.dropFirst(1))) {
                mentionsAsTags.append(NostrTag(["p", mention])) // TODO: ADD RELAY HINT
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
func nip10OrderedTags(oldTags:[NostrTag], mentionedTags:[NostrTag]) -> [NostrTag] {
    if oldTags.isEmpty {
        return mentionedTags
    }
    var newTags:[NostrTag] = []
    
    // Last "E" should always be the reply to be compatible with old clients
    if (oldTags.filter { $0.type == "e" }.count == 1 && oldTags.filter { $0.type == "e" }.first?.tag[safe: 3] != "mention") {
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
func replaceTagsWithIndexes(_ text:String, tags:[NostrTag], bumpIndex:Bool) -> String {
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
    let hashtags = event.content.matchingStrings(regex:"(?<![/\\?]|\\b)(\\#)([^\\s\\[]{2,})\\b")
        .map { String( $0[0].dropFirst()) }
    
    var eventWithHashtags = event
    for hashtag in hashtags {
        eventWithHashtags
            .tags
            .append(
                NostrTag(["t", hashtag])
            )
        
        // Also add lowercase tag if it's not already lowercase
        if hashtag != hashtag.lowercased() {
            if !hashtags.contains(hashtag.lowercased()) {
                eventWithHashtags
                    .tags
                    .append(
                        NostrTag(["t", hashtag.lowercased()])
                    )
            }
        }
    }
    return eventWithHashtags
}
