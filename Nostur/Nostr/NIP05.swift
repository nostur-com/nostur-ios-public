//
//  NIP05.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/02/2023.
//

import Foundation
import CoreData

struct NostrJson : Codable {
    var names: [String:String]
}

class NIP05 {
    
    static var twoWeeksAgo:Date {
        get { Date.now.addingTimeInterval(-(14 * 86400)) }
    }
    
    static func shouldVerify(_ contact:Contact) -> Bool {
        guard contact.nip05 != nil else {
            return false
        }
        return (contact.nip05 != nil && contact.nip05verifiedAt == nil) || (contact.nip05verifiedAt != nil) && (contact.nip05verifiedAt! < self.twoWeeksAgo)
    }
    
    static func verify(nip05:String, expectedPubkey:String) async -> Bool {
        let nip05trimmed = nip05.trimmingCharacters(in: .whitespacesAndNewlines)
        let nip05parts = nip05trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        
        guard nip05parts.count == 2 else { return false }
        
        let nip05url = URL(string: "https://\(nip05parts[1])/.well-known/nostr.json?name=\(nip05parts[0])")!
        let urlSession = URLSession.shared
        
        do {
            let (data, _) = try await urlSession.data(from: nip05url)
            let nostrJson = try JSONDecoder().decode(NostrJson.self, from: data)
            if let pubkey = nostrJson.names[String(nip05parts[0])] {
                if pubkey != "" && pubkey == expectedPubkey {
                    return true
                }
                return false
            }
            else {
                print("🔴🔴 trouble parsing nostr.json ")
            }
            return false
        }
        catch {
            debugPrint("Error loading \(nip05url): \(String(describing: error))")
            return false
        }
    }
}
