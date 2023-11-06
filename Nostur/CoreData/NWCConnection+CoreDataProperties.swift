//
//  NWCConnection+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//
//

import Foundation
import CoreData

extension NWCConnection {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NWCConnection> {
        return NSFetchRequest<NWCConnection>(entityName: "NWCConnection")
    }

    @NSManaged public var connectionId: String // Use this to fetch key from keychain
    @NSManaged public var pubkey: String // our public key to send/receive commands with
    @NSManaged public var walletPubkey: String // wallet provider key
    @NSManaged public var createdAt: Date
    @NSManaged public var relay: String // NIP-47, can be multiple according to spec, but is not defined how more than one is entered, comma?
    @NSManaged public var methods: String
    @NSManaged public var type: String? // "CUSTOM", "ALBY", ...

}

extension NWCConnection : Identifiable {
    
    static func createAlbyConnection(context: NSManagedObjectContext) -> NWCConnection {
        let c = NWCConnection(context: context)
        c.createdAt = .now
        c.connectionId = UUID().uuidString
        c.pubkey = NIP47SecretManager.shared.generateKeysForConnection(c)
        c.type = "ALBY"
        return c
    }
    
    static func createCustomConnection(context: NSManagedObjectContext, secret:String) -> NWCConnection? {
        let c = NWCConnection(context: context)
        c.createdAt = .now
        c.connectionId = UUID().uuidString
        guard let existingKeys = try? NKeys(privateKeyHex: secret) else { return nil }
        NIP47SecretManager.shared.storeSecret(existingKeys, connectionId: c.connectionId)
        c.pubkey = existingKeys.publicKeyHex()
        c.type = "CUSTOM"
        return c
    }
    
    static func fetchConnection(_ connectionId:String, context:NSManagedObjectContext) -> NWCConnection? {
        guard !connectionId.isEmpty else { return nil }
        let fr = NWCConnection.fetchRequest()
        fr.predicate = NSPredicate(format: "connectionId == %@", connectionId)
        return try? context.fetch(fr).first
    }
    
    static func delete(_ connectionId:String, context:NSManagedObjectContext) {
        guard !connectionId.isEmpty else { return }
        let fr = NWCConnection.fetchRequest()
        fr.predicate = NSPredicate(format: "connectionId == %@", connectionId)
        if let connection = try? context.fetch(fr).first {
            context.delete(connection)
        }
    }
    
    func delete() { // Deletes connection from database, also removes key from keychain
        L.og.info("NWCConnection.delete: \(self.connectionId) (will also remove key from keychain")
        let ctx = bg()
        ctx.perform {
            NIP47SecretManager.shared.deleteSecret(connectionId: self.connectionId)
            ctx.delete(self)
            DataProvider.shared().bgSave()
        }
    }
    
    var privateKey:String? {
        get {
            return NIP47SecretManager.shared.getSecret(connectionId: self.connectionId)
        }
    }
}
