//
//  SearchModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2025.
//

import Foundation

class SearchModel {
    
    
    
    private func searchInNames(_ terms: String) {
        let terms = terms.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            .map(String.init)
        let blockedPubkeys = blocks()
        
        var matchingPubkeys: [String: Set<String>] = [:]
        var matchingPostIds: [String: Set<String>] = [:]
        
        var completeMatches: [String: Int] = [:]
        
        bg().perform {
            
            
            for term in terms {
                let fr = Contact.fetchRequest()
                fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                fr.predicate = NSPredicate(format: "NOT pubkey IN %@ AND (name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@ OR fixedName CONTAINS[cd] %@ OR nip05 CONTAINS[cd] %@)", blockedPubkeys, term, term, term, term)
                fr.fetchLimit = 5000
                
                if let results = try? bg().fetch(fr) {
                    matchingPubkeys[term] = Set(results.map(\Contact.pubkey))
                }
            }
            
            for term in terms {
                let fr = Event.fetchRequest()
                fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                fr.predicate = NSPredicate(format: "NOT pubkey IN %@ AND kind == 1 AND content CONTAINS[cd] %@ AND NOT content BEGINSWITH %@", blockedPubkeys, term, "lnbc")
                fr.fetchLimit = 5000
                
                if let results = try? bg().fetch(fr) {
                    matchingPostIds[term] = Set(results.map(\Event.id))
                }
            }
            
            for term in terms {
                if !((matchingPubkeys[term]?.isEmpty ?? true)) || !((matchingPostIds[term]?.isEmpty ?? true)) {
                    
                }
            }
           
        }
    }
}
