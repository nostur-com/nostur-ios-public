//
//  Mentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import Foundation

func replaceSemanticMentionsWithNpubs(_ attributedText: NSAttributedString) -> String {
    let mutableText = NSMutableString(string: attributedText.string)
    let mentionRuns = attributedText.nosturMentionRuns()
        .sorted { $0.range.location > $1.range.location }

    for mention in mentionRuns {
        guard let npub = try? NIP19(
            prefix: "npub",
            hexString: mention.pubkey
        ).displayString else { continue }
        mutableText.replaceCharacters(
            in: mention.range,
            with: "nostr:\(npub)"
        )
    }
    return mutableText as String
}

// Replace "@npub1..." with "nostr:npub1..." and return an array of all
// replaced npubs for turning into pTags
func replaceAtWithNostr(_ input:String) -> (String, [String]) {
    let regex = try! NSRegularExpression(pattern: "@(npub1[023456789acdefghjklmnpqrstuvwxyz]{58})", options: [])
    var matches: [String] = []
    
    let newString = regex.stringByReplacingMatches(in: input, options: [], range: NSRange(input.startIndex..., in: input), withTemplate: "nostr:$1")
    
    regex.enumerateMatches(in: input, options: [], range: NSRange(input.startIndex..., in: input)) { result, _, _ in
        if let range = result?.range(at: 1), let swiftRange = Range(range, in: input) {
            matches.append(String(input[swiftRange]))
        }
    }
    
    return (newString, matches)
}


// Scan for any "nostr:npub1..." and return as array of npubs
// so they can be added to pTags
func getNostrNpubs(_ input:String) -> [String] {
    do {
        let regex = try NSRegularExpression(pattern: "nostr:(npub1[023456789acdefghjklmnpqrstuvwxyz]{58})")
        let results = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        return results.compactMap {
            Range($0.range(at: 1), in: input).map { String(input[$0]) }
        }
    } catch {
        return []
    }
}

import NostrEssentials

// Scan for any "nostr:note1..." or "nostr:nevent" and return as array of q tags
// so they can be added to qTags
func getQuoteTags(_ input: String) -> [String] {

    let r = NostrRegexes.default
    
    let qTags: [String] = r.matchingStrings(input, regex: r.cache[.nostrUri]!)
        .compactMap { match in
            guard match.count == 3 else { return nil }
            if match[2] == "note1" {
                return NostrEssentials.Keys.hex(npub: match[1]) // TODO: update npub: to note:1 for readability
            }
            else if match[2] == "nevent1" {
                return (try? NostrEssentials.ShareableIdentifier(match[1]))?.id
            }
            return nil
        }
    
    return qTags
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

func putHashtagsInTags(_ event: NEvent, content: String) -> NEvent {
    let hashtags = content.matchingStrings(regex:"(?<![/\\?]|\\b)(\\#)([^\\s\\[]{2,})\\b")
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
