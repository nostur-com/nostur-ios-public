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
    
    static var fourWeeksAgo:Date {
        get { Date.now.addingTimeInterval(-(28 * 86400)) }
    }
    
    static func shouldVerify(_ contact:Contact) -> Bool {
        guard contact.nip05 != nil else {
            return false
        }
        return (contact.nip05 != nil && contact.nip05verifiedAt == nil) || (contact.nip05verifiedAt != nil) && (contact.nip05verifiedAt! < self.fourWeeksAgo)
    }
    
    static func verify(nip05:String, expectedPubkey:String) async -> Bool {
        let nip05trimmed = nip05.trimmingCharacters(in: .whitespacesAndNewlines)
        let nip05parts = nip05trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        
        guard nip05parts.count == 2 else { return false }
        
        guard let nip05url = URL(string: "https://\(nip05parts[1])/.well-known/nostr.json?name=\(nip05parts[0])") else { return false }
        
        guard FailedURLCache.shared.retrieveObject(at: String(nip05parts[1])) == nil else {
            print("\(String(nip05parts[1])) already failed before, skipping")
            return false
        }
        
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
        catch let error as NSError where
             error.domain == NSURLErrorDomain &&
                error.code == NSURLErrorSecureConnectionFailed {
            print("NSURLErrorSecureConnectionFailed")
            FailedURLCache.shared.setObject(for: String(nip05parts[1]), value: Date.now)
            return false
        }
        catch let error as NSError where
             error.domain == NSURLErrorDomain &&
                error.code == NSURLErrorTimedOut {
            print("timed out!")
            return false
        }
        catch {
            print("Error loading \(nip05url): \(String(describing: error))")
            // TODO: add to failed cache so we dont keep trying over and over until 4h later maybe
            // example: Error Domain=NSURLErrorDomain Code=-1200 "An SSL error has occurred and a se..."
            return false
        }
    }
    
    static func verifyBatch(contacts:[Contact], context:NSManagedObjectContext) {
        var unverified = [(NSManagedObjectID, String, String)]()
        for contact in contacts.prefix(8) {
            unverified.append((contact.objectID, contact.nip05!, contact.pubkey))
        }
               
        let unverifiedCaptured = unverified
        let basicTask = Task {
            var verified = [(NSManagedObjectID, String, String)]()
            for tuple in unverifiedCaptured {
                if await NIP05.verify(nip05: tuple.1, expectedPubkey: tuple.2) {
                    verified.append(tuple)
                }
            }
            return verified
        }
        
        Task {
            let verifiedCaptured = await basicTask.value
            await context.perform {
                for tuple in verifiedCaptured {
                    guard let contact = context.object(with: tuple.0) as? Contact else { continue }
                    contact.nip05verifiedAt = Date.now
                }
            }
        }
    }
}
