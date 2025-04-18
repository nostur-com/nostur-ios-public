//
//  SearchModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2025.
//

import Foundation


typealias SearchTerm = String

class SearchModel {
    
    // if I'm searching for 3 words then it should search in
    // - names
    // - content
    // all 3 words should be matched
    
    @MainActor
    static public func searchInNames(_ terms: String) async -> ([NRContact], [NRPost]) {
        await withCheckedContinuation { continuation in
            
            let terms: Set<SearchTerm> = Set(
                                                terms.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    .split(separator: " ")
                                                    .map(String.init)
                                            )
            let blockedPubkeys = blocks()
            
            var matchedTermsForContactName: [Pubkey: Set<SearchTerm>] = [:]
            var matchedTermsForPostContent: [PostID: Set<SearchTerm>] = [:]
            var postPubkeys: [PostID: Pubkey] = [:]
            
            bg().perform {
                for term in terms {
                    let fr = Contact.fetchRequest()
                    fr.predicate = NSPredicate(format: "NOT pubkey IN %@ AND (name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@ OR fixedName CONTAINS[cd] %@ OR nip05 CONTAINS[cd] %@)", blockedPubkeys, term, term, term, term)
                    
                    if let contacts = try? bg().fetch(fr) {
                        for contact in contacts {
                            if matchedTermsForContactName[contact.pubkey] == nil {
                                matchedTermsForContactName[contact.pubkey] = Set<SearchTerm>()
                            }
                            matchedTermsForContactName[contact.pubkey]?.insert(term)
                        }
                    }
                }
                
                for term in terms {
                    let fr = Event.fetchRequest()
                    fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                    fr.predicate = NSPredicate(format: "NOT pubkey IN %@ AND kind IN {1,20,9802} AND content CONTAINS[cd] %@ AND NOT content BEGINSWITH %@", blockedPubkeys, term, "lnbc")
                    
                    if let posts = try? bg().fetch(fr) {
                        for post in posts {
                            if matchedTermsForPostContent[post.id] == nil {
                                matchedTermsForPostContent[post.id] = Set<SearchTerm>()
                            }
                            matchedTermsForPostContent[post.id]?.insert(term)
                            postPubkeys[post.id] = post.pubkey
                        }
                    }
                }
                
                
                // show contact if
                // all terms are in matchedTermsForContactName
                let contactResults: [Pubkey] = matchedTermsForContactName
                    .filter { (key: Pubkey, value: Set<SearchTerm>) in
                        value.count == terms.count
                    }
                    .map { $0.key }
                
                // show post if
                // all terms are in matchedTermsForPostContent
                let postResults: [PostID] = matchedTermsForPostContent
                    .filter { (key: PostID, value: Set<SearchTerm>) in
                        value.count == terms.count
                    }
                    .map { $0.key }

                // show post if
                // post + contactname .union.count equal terms.count
                let postAndContactNameResults: [PostID] = matchedTermsForPostContent
                    .filter { (key: PostID, value: Set<SearchTerm>) in
                        matchedTermsForContactName[postPubkeys[key] ?? ""]?.union(matchedTermsForPostContent[key] ?? []).count ?? 0 == terms.count
                    }
                    .map { $0.key }
               
                
                let fr2 = Contact.fetchRequest()
                fr2.predicate = NSPredicate(format: "pubkey IN %@", contactResults)
                
                let contactsResult: [Contact] = (try? bg().fetch(fr2)) ?? []
                
                let wot = WebOfTrust.shared
                let nrContactsResult: [NRContact] = if WOT_FILTER_ENABLED() {
                    contactsResult.compactMap { NRContact.fetch($0.pubkey, contact: $0) }
                        // WoT enabled, so put in-WoT before non-WoT
                        .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                        // Put following before non-following
                        .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
                }
                else {
                    contactsResult.compactMap { NRContact.fetch($0.pubkey, contact: $0) }
                        // Put following before non-following
                        .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
                }
                
                let allPostResults: Set<PostID> = Set(postResults + postAndContactNameResults)
                let fr3 = Event.fetchRequest()
                fr3.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                fr3.predicate = NSPredicate(format: "id IN %@", allPostResults)
                
                let postsResult: [Event] = (try? bg().fetch(fr3)) ?? []
                let nrPostsResult: [NRPost] = if WOT_FILTER_ENABLED() {
                    postsResult.map { NRPost(event: $0) } // TODO: NRPost cache???
                        // WoT enabled, so put in-WoT before non-WoT
                        .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                        // Put following before non-following
                        .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
                }
                else {
                    postsResult.map { NRPost(event: $0) } // TODO: NRPost cache???
                        // Put following before non-following
                        .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
                }
                
                continuation.resume(returning: (nrContactsResult, nrPostsResult))
            }
        }
    }
}
