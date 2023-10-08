//
//  Mentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import Foundation

func replaceMentionsWithNpubs(_ text:String, selected:Set<Contact> = []) -> String {
    let blocked:Set<String> = blocks()
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
            newText = newText.replacingOccurrences(of: mention.output.2, with: "nostr:\(result.npub)", options: [.caseInsensitive])
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
            newText = newText.replacingOccurrences(of: mention.output.2, with: "nostr:\(result.npub)", options: [.caseInsensitive])
            continue
        }
                
        
        else if let result = try? DataProvider.shared().viewContext.fetch(fr).first {
//            print("any! result \(result.handle) \(result.npub)")
            newText = newText.replacingOccurrences(of: mention.output.2, with: "nostr:\(result.npub)", options: [.caseInsensitive])
        }
    }
    return newText
}

func toHex(_ bech:String) -> String? {
    guard let nip19 = try? NIP19(displayString: bech) else { return nil }
    return nip19.hexString
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
