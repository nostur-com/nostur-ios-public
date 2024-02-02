//
//  CloudAccount+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/11/2023.
//
//

import Foundation
import CoreData
import CloudKit

extension CloudAccount {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudAccount> {
        return NSFetchRequest<CloudAccount>(entityName: "CloudAccount")
    }

    @NSManaged public var about_: String?
    @NSManaged public var banner_: String?
    @NSManaged public var blockedPubkeys: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var display_name_: String?
    @NSManaged public var flags: String?
    @NSManaged public var followingHashtags_: String?
    @NSManaged public var followingPubkeys_: String?
    @NSManaged public var accountRelays_: String? // Account based relays (instead of app-shared)
    @NSManaged public var privateFollowingPubkeys_: String?
    @NSManaged public var isNC: Bool
    @NSManaged public var lastFollowerCreatedAt: Int64
    @NSManaged public var lastProfileReceivedAt: Date?
    @NSManaged public var lastSeenDMRequestCreatedAt: Int64
    @NSManaged public var lastSeenPostCreatedAt: Int64
    @NSManaged public var lastSeenReactionCreatedAt: Int64
    @NSManaged public var lastSeenRepostCreatedAt: Int64
    @NSManaged public var lastSeenZapCreatedAt: Int64
    @NSManaged public var lud06_: String?
    @NSManaged public var lud16_: String?
    @NSManaged public var mutedRootIds: String?
    @NSManaged public var name_: String?
    @NSManaged public var ncRelay_: String?
    @NSManaged public var nip05_: String?
    @NSManaged public var picture_: String?
    @NSManaged public var publicKey_: String?
    @NSManaged public var lastLoginAt_: Date? // Or "last use" via in-post switcher
    
    // -- MARK: Non-optional getters/setters
    
    public var about: String {
        get { about_ ?? "" }
        set { about_ = newValue }
    }
    
    public var banner: String {
        get { banner_ ?? "" }
        set { banner_ = newValue }
    }
    
    public var display_name: String {
        get { display_name_ ?? "" }
        set { display_name_ = newValue }
    }
    
    public var pictureUrl:URL? {
        guard let picture = picture_ else { return nil }
        return URL(string: picture)
    }
    
    var flagsSet:Set<String> {
        get {
            guard let flags else { return [] }
            return Set(flags.split(separator: " ").map { String($0) })
        }
        set {
            flags = newValue.joined(separator: " ")
        }
    }
    
    var followingHashtags:Set<String> {
        get {
            guard let followingHashtags_ else { return [] }
            return Set(followingHashtags_.split(separator: " ").map { String($0) })
        }
        set {
            followingHashtags_ = newValue.joined(separator: " ")
        }
    }
    
    var follows:[Contact] {
        get {
            let followsIncludingPrivate = followingPubkeys.union(privateFollowingPubkeys)
            return Contact.fetchByPubkeys(Array(followsIncludingPrivate), context: Thread.isMainThread ? DataProvider.shared().viewContext : bg())
        }
        set {
            guard let account = account() else { return }
            followingPubkeys_ = newValue.filter { !account.privateFollowingPubkeys.contains($0.pubkey) }.map { $0.pubkey }.joined(separator: " ")
            privateFollowingPubkeys_ = newValue.filter { account.privateFollowingPubkeys.contains($0.pubkey) }.map { $0.pubkey }.joined(separator: " ")
        }
    }
    
    var followingPubkeys:Set<String> {
        get {
            guard let followingPubkeys = followingPubkeys_ else { return [] }
            return Set(followingPubkeys.split(separator: " ").map { String($0) })
        }
        set {
            followingPubkeys_ = newValue.joined(separator: " ")
        }
    }
    
    var privateFollowingPubkeys:Set<String> {
        get {
            guard let privateFollowingPubkeys = privateFollowingPubkeys_ else { return [] }
            return Set(privateFollowingPubkeys.split(separator: " ").map { String($0) })
        }
        set {
            privateFollowingPubkeys_ = newValue.joined(separator: " ")
        }
    }
    
    var accountRelays:Set<AccountRelayData> {
        get {
            guard let accountRelays = accountRelays_, let data = accountRelays.data(using: .utf8) else { return [] }
            let decoder = JSONDecoder()
            guard let accountRelayData = try? decoder.decode([AccountRelayData].self, from: data) else { return [] }
            return Set(accountRelayData)
        }
        set {
            let encoder = JSONEncoder()
            guard let accountRelayJSONdata = try? encoder.encode(Array(newValue)) else { accountRelays_ = nil; return }
            accountRelays_ = String(data: accountRelayJSONdata, encoding: .utf8)
        }
    }
    
    public var lud06: String {
        get { lud06_ ?? "" }
        set { lud06_ = newValue }
    }
    
    public var lud16: String {
        get { lud16_ ?? "" }
        set { lud16_ = newValue }
    }
    
    public var name: String {
        get { name_ ?? "" }
        set { name_ = newValue }
    }
    
    public var ncRelay: String {
        get { ncRelay_ ?? "" }
        set { ncRelay_ = newValue }
    }
    
    public var nip05: String {
        get { nip05_ ?? "" }
        set { nip05_ = newValue }
    }
    
    public var picture: String {
        get { picture_ ?? "" }
        set { picture_ = newValue }
    }
    
    public var publicKey: String {
        get { publicKey_ ?? "" }
        set { publicKey_ = newValue }
    }
    
    public var mostRecentItemDate:Int64 { // Used for duplicate accounts in iCloud, to resolve which one to keep (most recent)
        return [
            Int64((createdAt ?? .distantPast).timeIntervalSince1970),
            lastSeenRepostCreatedAt,
            lastSeenPostCreatedAt,
            lastSeenZapCreatedAt,
            lastSeenReactionCreatedAt,
            lastFollowerCreatedAt,
            Int64((lastProfileReceivedAt ?? .distantPast).timeIntervalSince1970),
            lastSeenDMRequestCreatedAt,
            
        ].sorted(by: >).first!
    }

    public var lastLoginAt: Date {
        get { lastLoginAt_ ?? .distantPast }
        set { lastLoginAt_ = newValue }
    }
    
}

extension CloudAccount : Identifiable {

    var anyName:String {
        if name != "" { return name }
        if display_name != "" { return display_name }
        return String(npub.prefix(11))
    }
    
    var npub:String { try! NIP19(prefix: "npub", hexString: publicKey).displayString }
    
    var isFullAccount: Bool {
        return self.flagsSet.contains("full_account")
    }
    
    var privateKey:String? {
        get {
            if noPrivateKey { return nil }
            if isNC {
                if let key = NIP46SecretManager.shared.getSecret(account: self) {
                    noPrivateKey = false
                    return key
                }
                return nil
            }
            
            if let key = AccountManager.shared.getPrivateKeyHex(pubkey: self.publicKey, account: self) {
                noPrivateKey = false
                return key
            }
            else {
                return nil
            }
        }
        set(privateKeyHex) {
            guard privateKeyHex != nil else {
                AccountManager.shared.deletePrivateKey(forPublicKeyHex: self.publicKey)
                return
            }
            noPrivateKey = false
            AccountManager.shared.storePrivateKey(privateKeyHex: privateKeyHex!, forPublicKeyHex: self.publicKey)
        }
    }
    
    var nsec:String? {
        get {
            guard self.privateKey != nil else { return nil }
            guard let nsec = try? NIP19(prefix: "nsec", hexString: self.privateKey!).displayString else {
                return nil
            }
            return nsec
        }
    }
    
    
    // For when adding read only accounts, prefill with kind.0 info from relays (FROM CACHE)
    static func preFillReadOnlyAccountInfo(account:CloudAccount, context:NSManagedObjectContext, forceOverwrite:Bool = false) {
        
        guard let kind0 = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: context)?.first else {
            return
        }
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: kind0.content!.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }

        if (account.privateKey == nil || forceOverwrite) { // Don't overwrite non-read-only accounts
            account.objectWillChange.send()
            account.name = metaData.name ?? ""
            if account.name == "" { // fallback
                account.name = metaData.display_name ?? ""
            }
            account.about = metaData.about ?? ""
            account.picture = metaData.picture ?? ""
            account.banner = metaData.banner ?? ""
            account.nip05 = metaData.nip05 ?? ""
            account.lud16 = metaData.lud16 ?? ""
            account.lud06 = metaData.lud06 ?? ""
        }
    }
    
    // For when adding read only accounts, prefill with kind.0 info from relays (NEW EVENT FROM IMPORTER)
    static func preFillReadOnlyAccountInfo(event:NEvent, context:NSManagedObjectContext, forceOverwrite:Bool = false) {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let fr = CloudAccount.fetchRequest()
        fr.predicate = NSPredicate(format: "publicKey_ = %@", event.publicKey)
        if let account = try? context.fetch(fr).first {
            if (account.privateKey == nil || forceOverwrite == true) { // Don't overwrite non-read-only accounts
                account.objectWillChange.send()
                account.name = metaData.name ?? ""
                if account.name == "" { // fallback
                    account.name = metaData.display_name ?? ""
                }
                account.about = metaData.about ?? ""
                account.picture = metaData.picture ?? ""
                account.banner = metaData.banner ?? ""
                account.nip05 = metaData.nip05 ?? ""
                account.lud16 = metaData.lud16 ?? ""
                account.lud06 = metaData.lud06 ?? ""
            }
        }
    }
    
    // For when adding read only accounts, prefill with kind.3 info from relays (FROM CACHE)
    static func preFillReadOnlyAccountFollowing(account:CloudAccount, context:NSManagedObjectContext) {
        
        guard let kind3 = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: context)?.first else {
            return
        }
        
        let contacts = Contact.ensureContactsCreated(event: kind3.toNEvent(), context: context, limit:999)
        
        // if read only account, import follows. Or pendingFirstContactsFetch
        if (!contacts.isEmpty) {
//            account.objectWillChange.send()
            for contact in contacts {
                account.followingPubkeys.insert(contact.pubkey)
            }
        }
    }
    
    func toBG() -> CloudAccount? {
        bg().object(with: self.objectID) as? CloudAccount
    }
    
    
    func signEvent(_ event:NEvent) throws -> NEvent {
        guard let privateKey = self.privateKey else {
            L.og.error("🔴🔴🔴🔴🔴 private key missing, could not sign 🔴🔴🔴🔴🔴")
            throw "account or keys missing, could not sign"
        }
        
        var eventToSign = event
        do {
            let keys = try NKeys(privateKeyHex: privateKey)
            let signedEvent = try eventToSign.sign(keys)
            return signedEvent
        }
        catch {
            L.og.error("🔴🔴🔴🔴🔴 Could not sign event 🔴🔴🔴🔴🔴")
            throw "Could not sign event"
        }
    }
    
    func signEventBg(_ event:NEvent) throws -> NEvent {
        guard let account = self.toBG() else {
            L.og.error("🔴🔴🔴🔴🔴 Acccount missing, could not sign 🔴🔴🔴🔴🔴")
            throw "account missing, could not sign"
        }
        guard let pk = account.privateKey else {
            L.og.error("🔴🔴🔴🔴🔴 private key missing, could not sign 🔴🔴🔴🔴🔴")
            throw "keys missing, could not sign"
        }
        
        var eventToSign = event
        do {
            let keys = try NKeys(privateKeyHex: pk)
            let signedEvent = try eventToSign.sign(keys)
            return signedEvent
        }
        catch {
            L.og.error("🔴🔴🔴🔴🔴 Could not sign event 🔴🔴🔴🔴🔴")
            throw "Could not sign event"
        }
    }
    
    static func fetchAccount(publicKey:String, context:NSManagedObjectContext) throws -> CloudAccount? {
        let request = NSFetchRequest<CloudAccount>(entityName: "CloudAccount")
        request.predicate = NSPredicate(format: "publicKey_ = %@", publicKey)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
    static func fetchAccounts(context:NSManagedObjectContext) -> [CloudAccount] {
        let request = NSFetchRequest<CloudAccount>(entityName: "CloudAccount")
        request.predicate = NSPredicate(value: true)
        return (try? context.fetch(request)) ?? []
    }
    
    
    func toStruct() -> AccountData {
        AccountData(publicKey: publicKey,
                    lastSeenPostCreatedAt: lastSeenPostCreatedAt,
                    followingPubkeys: followingPubkeys,
                    privateFollowingPubkeys: privateFollowingPubkeys,
                    followingHashtags: followingHashtags,
                    picture: picture_,
                    flags: flagsSet,
                    isNC: isNC,
                    anyName: anyName
        )
    }
}
