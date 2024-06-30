//
//  Mentions.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import Foundation

@available(iOS 16.0, *)
func replaceMentionsWithNpubs(_ text: String, selected: Set<Contact> = []) -> String {
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

func replaceMentionsWithNpubs15(_ text: String, selected: Set<Contact> = []) -> String {
    let blocked: Set<String> = blocks()
    let regexPattern = "(?:^|\\s)((@(\\x{2063}\\x{2064}[^\\x{2063}\\x{2064}]+\\x{2064}\\x{2063}|\\w+)))"
    var newText = text

    do {
        let regex = try NSRegularExpression(pattern: regexPattern, options: [])
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        let mentionsByLongest = matches.sorted(by: {
            let range1 = Range($0.range(at: 3), in: text)!
            let range2 = Range($1.range(at: 3), in: text)!
            return text.distance(from: range1.lowerBound, to: range1.upperBound) >
                   text.distance(from: range2.lowerBound, to: range2.upperBound)
        })

        for match in mentionsByLongest {
            let termRange = match.range(at: 3)
            guard let termSwiftRange = Range(termRange, in: text),
                  let mentionRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let term = text[termSwiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .replacingOccurrences(of: "\u{2063}", with: "")
                        .replacingOccurrences(of: "\u{2064}", with: "")
            let mention = text[mentionRange]

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
                newText = newText.replacingOccurrences(of: mention, with: "nostr:\(result.npub)", options: [.caseInsensitive])
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
                newText = newText.replacingOccurrences(of: mention, with: "nostr:\(result.npub)", options: [.caseInsensitive])
                continue
            }
            
            
            else if let result = try? DataProvider.shared().viewContext.fetch(fr).first {
                //            print("any! result \(result.handle) \(result.npub)")
                newText = newText.replacingOccurrences(of: mention, with: "nostr:\(result.npub)", options: [.caseInsensitive])
            }
        }
    } catch {
        L.og.debug("Regex error: \(error)")
        return newText
    }

    return newText
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
func getQuoteTags(_ input:String) -> [String] {

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
