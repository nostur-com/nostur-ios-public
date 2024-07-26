//
//  NRChatMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/07/2024.
//

import Foundation
import Combine

// NRChatMessage SHOULD BE CREATED IN BACKGROUND THREAD
class NRChatMessage: ObservableObject, Identifiable, Hashable, Equatable {
    
    
//    class PFPAttributes: ObservableObject {
//        @Published var contact: NRContact? = nil
//        private var contactSavedSubscription: AnyCancellable?
//        
//        init(contact: NRContact? = nil, pubkey: String) {
//            self.contact = contact
//            
//            if contact == nil {
//                contactSavedSubscription = ViewUpdates.shared.contactUpdated
//                    .filter { pubkey == $0.pubkey }
//                    .sink(receiveValue: { [weak self] contact in
//                        let nrContact = NRContact(contact: contact, following: isFollowing(contact.pubkey))
//                        DispatchQueue.main.async { [weak self] in
//                            self?.objectWillChange.send()
//                            self?.contact = nrContact
//                        }
//                        self?.contactSavedSubscription?.cancel()
//                        self?.contactSavedSubscription = nil
//                    })
//            }
//        }
//        
//        
//        // Listen here or somewhere in view?
//    }
    
    var pfpAttributes: PFPAttributes
    var zapFromAttributes: ZapFromAttributes?

    let SPAM_LIMIT_P: Int = 50
 
    static func == (lhs: NRChatMessage, rhs: NRChatMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let nEvent: NEvent
    public var createdAt: Date { Date(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp)) }
    public var created_at: Int64 { Int64(nEvent.createdAt.timestamp) }
    
    var id: NRPostID { nEvent.id }
        
    var pubkey: String { nEvent.publicKey }
        
    var content: String?
    
    var contentElementsDetail: [ContentElement] = [] // PostDetail.Kind1
    var via: String?
    
    var contact: NRContact?  {
        get { pfpAttributes.contact }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.pfpAttributes.contact = newValue
            }
        }
    }
        
//    var replyToId: String?
//    var replyToRootId: String?
//    
//    var _replyTo: NRChatMessage?
//    var _replyToRoot: NRChatMessage?
    
    
//    var replyTo: NRChatMessage?  {
//        get { NRState.shared.nrPostQueue.sync { [weak self] in
//            self?._replyTo
//        } }
//        set { NRState.shared.nrPostQueue.async(flags: .barrier) { [weak self] in
//            self?._replyTo = newValue
//        } }
//    }
//    
//    var replyToRoot: NRChatMessage? {
//        get { NRState.shared.nrPostQueue.sync { [weak self] in
//            self?._replyToRoot
//        } }
//        set { NRState.shared.nrPostQueue.async(flags: .barrier) { [weak self] in
//            self?._replyToRoot = newValue
//        } }
//    }
//    
    var firstE: String? // Needed for muting
      
    var missingPs: Set<String> // missing or have no contact info
    var fastTags: [(String, String, String?, String?, String?)] = []
    var hashtags: Set<String> = [] // lowercased hashtags for fast hashtag blocking

    var following = false
   
    var linkPreviewURLs: [URL] = []
    var imageUrls: [URL] = []
    
    var plainTextOnly = false
    
    var anyName: String?
    
//    var anyName: String {
//        if let contact = contact {
//            return contact.anyName
//        }
//        return String(pubkey.suffix(11))
//    }
     
    let inWoT: Bool // This is just one of the inputs to determine spam or not, should have more inputs.
    
    var isNSFW: Bool = false
    
    init(nEvent: NEvent) {
        
        self.nEvent = nEvent
        self.inWoT = WebOfTrust.shared.isAllowed(nEvent.publicKey)
        
        let fastTags: [(String, String, String?, String?, String?)] = nEvent.tags.map { ($0.type, $0.value, $0.tag[safe: 2], $0.tag[safe: 3], $0.tag[safe: 4]) }
        let fastPs: [(String, String, String?, String?, String?)] = fastTags.filter { $0.0 == "p" }
        
        
        // Show if ["client", "Name", ""31990:..." ...]
        // Hide if ["client", ""31990:..." ..]
        // Also show if  ["proxy", "https:\/\/....", "activitypub"]
        self.via = fastTags.first(where: { $0.0 == "client" && $0.1.prefix(6) != "31990:" })?.1
        if self.via == nil {
            if let proxy = fastTags.first(where: { $0.0 == "proxy" && $0.2 != nil })?.2 {
                self.via = String(format: "%@ (proxy)", proxy)
            }
        }
        
        let pTags = fastPs.map { $0.1 }
        let cachedContacts = pTags.compactMap { NRContactCache.shared.retrieveObject(at: $0) }
        let cachedContactPubkeys = Set(cachedContacts.map { $0.pubkey })
        let uncachedPtags = pTags.filter { !cachedContactPubkeys.contains($0)  }
        
        let contactsFromDb = Contact.fetchByPubkeys(uncachedPtags).map { contact in
            let nrContact = NRContact(contact: contact)
            NRContactCache.shared.setObject(for: contact.pubkey, value: nrContact)
            return nrContact
        }
        
        let referencedContacts = cachedContacts + contactsFromDb
        
        var anyName: String?
        
        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: nEvent.publicKey) {
            self.pfpAttributes = PFPAttributes(contact: cachedNRContact, pubkey: nEvent.publicKey)
            anyName = cachedNRContact.contact?.anyName
        }
        else if let contact = Contact.contactBy(pubkey: nEvent.publicKey, context: bg()) {
            self.pfpAttributes = PFPAttributes(contact: NRContact(contact: contact, following: self.following), pubkey: nEvent.publicKey)
            anyName = contact.anyName
        }
        else {
            self.pfpAttributes = PFPAttributes(pubkey: nEvent.publicKey)
            anyName = String(nEvent.publicKey.suffix(11))
        }
        
        self.anyName = anyName
        
        var missingPs = Set<String>()
        if self.pfpAttributes.contact == nil {
            missingPs.insert(nEvent.publicKey)
        }
        else if let c = self.pfpAttributes.contact?.contact, c.metadata_created_at == 0 {
            missingPs.insert(nEvent.publicKey)
        }
        let eventContactPs = (referencedContacts.compactMap({ contact in
            if (contact.contact?.metadata_created_at ?? 0) != 0 {
                return contact.pubkey
            }
            return nil
        }) + [nEvent.publicKey])
        
        // Some clients put P in kind 6. Ignore that because the contacts are in the reposted post, not in the kind 6.
        // TODO: Should only fetch if the Ps are going to be on screen. Could be just for notifications.
        fastPs.prefix(SPAM_LIMIT_P).forEach { (tag, pubkey, hint, _, _) in
            if !eventContactPs.contains(pubkey) {
                missingPs.insert(pubkey)
            }
        }
        
        let (contentElementsDetail, linkPreviewURLs, imageUrls) = NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags)
        self.linkPreviewURLs = linkPreviewURLs
        self.imageUrls = imageUrls
        
        self.contentElementsDetail = contentElementsDetail
        
        self.following = isFollowing(nEvent.publicKey)
        
        self.missingPs = missingPs
        
        self.content = nEvent.content
        self.isNSFW = self.hasNSFWContent()
        
        if nEvent.kind == .zapNote, let description = fastTags.first(where: { $0.0 == "description" })?.1 {
            guard let dataFromString = description.data(using: .utf8, allowLossyConversion: false) else {
                return
            }
            
            let decoder = JSONDecoder()
            guard var relayMessage = try? decoder.decode(NMessage.self, from: dataFromString) else {
                return
            }

            guard let zapFromNevent = relayMessage.event else {
                return
            }
            
            self.zapFromAttributes = ZapFromAttributes(nEvent: zapFromNevent)
        }
    }
    
    private func hasNSFWContent() -> Bool {
        // event contains nsfw hashtag?
        return fastTags.first(where: { $0.0 == "t" && $0.1.lowercased() == "nsfw" }) != nil
        
        // TODO: check labels/reports
    }
    
    private static func isBlocked(pubkey:String) -> Bool {
        return Nostur.blocks().contains(pubkey)
    }
    
    
    
    
    

    
    

    
    private func rebuildContentElements() {
        bg().perform { [weak self] in
            guard let self = self else { return }
            
            let (contentElementsDetail, _, _) =  NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags)
            
            DispatchQueue.main.async { [weak self] in
                // self.objectWillChange.send() // Not needed? because this is only for things not on screen yet
                // for on screen we already use .onReceive
                // if it doesn't work we need to change let nrPost:NRPost to @ObserverdObject var nrPost:NRPost on ContentRenderer
                // and enable self.objectWillChange.send() here.
                self?.contentElementsDetail = contentElementsDetail
            }
        }
    }
    

}



class ZapFromAttributes: ObservableObject  {
    var pfpAttributes: PFPAttributes
    let nEvent: NEvent
    var pubkey: String { nEvent.publicKey }
    public var createdAt: Date { Date(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp)) }
    public var created_at: Int64 { Int64(nEvent.createdAt.timestamp) }
    
    var id: NRPostID { nEvent.id }
        
    var content: String?
    var contentElementsDetail: [ContentElement] = [] // PostDetail.Kind1
    var via: String?
    
    var contact: NRContact?  {
        get { pfpAttributes.contact }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.pfpAttributes.contact = newValue
            }
        }
    }
    
    var following = false
   
    var linkPreviewURLs: [URL] = []
    var imageUrls: [URL] = []
    
    var plainTextOnly = false
    
    var anyName: String?
    
    let inWoT: Bool // This is just one of the inputs to determine spam or not, should have more inputs.
    
    
    var missingPs: Set<String> // missing or have no contact info
    var fastTags: [(String, String, String?, String?, String?)] = []
    
    var isNSFW: Bool = false
    
    init(nEvent: NEvent) {
        
        self.nEvent = nEvent
        self.inWoT = WebOfTrust.shared.isAllowed(nEvent.publicKey)
        
        let fastTags: [(String, String, String?, String?, String?)] = nEvent.tags.map { ($0.type, $0.value, $0.tag[safe: 2], $0.tag[safe: 3], $0.tag[safe: 4]) }
        let fastPs: [(String, String, String?, String?, String?)] = fastTags.filter { $0.0 == "p" }
        
        
        // Show if ["client", "Name", ""31990:..." ...]
        // Hide if ["client", ""31990:..." ..]
        // Also show if  ["proxy", "https:\/\/....", "activitypub"]
        self.via = fastTags.first(where: { $0.0 == "client" && $0.1.prefix(6) != "31990:" })?.1
        if self.via == nil {
            if let proxy = fastTags.first(where: { $0.0 == "proxy" && $0.2 != nil })?.2 {
                self.via = String(format: "%@ (proxy)", proxy)
            }
        }
        
        let pTags = fastPs.map { $0.1 }
        let cachedContacts = pTags.compactMap { NRContactCache.shared.retrieveObject(at: $0) }
        let cachedContactPubkeys = Set(cachedContacts.map { $0.pubkey })
        let uncachedPtags = pTags.filter { !cachedContactPubkeys.contains($0)  }
        
        let contactsFromDb = Contact.fetchByPubkeys(uncachedPtags).map { contact in
            let nrContact = NRContact(contact: contact)
            NRContactCache.shared.setObject(for: contact.pubkey, value: nrContact)
            return nrContact
        }
        
        let referencedContacts = cachedContacts + contactsFromDb
        
        var anyName: String?
        
        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: nEvent.publicKey) {
            self.pfpAttributes = PFPAttributes(contact: cachedNRContact, pubkey: nEvent.publicKey)
            anyName = cachedNRContact.contact?.anyName
        }
        else if let contact = Contact.contactBy(pubkey: nEvent.publicKey, context: bg()) {
            self.pfpAttributes = PFPAttributes(contact: NRContact(contact: contact, following: self.following), pubkey: nEvent.publicKey)
            anyName = contact.anyName
        }
        else {
            self.pfpAttributes = PFPAttributes(pubkey: nEvent.publicKey)
            anyName = String(nEvent.publicKey.suffix(11))
        }
        
        self.anyName = anyName
        
        var missingPs = Set<String>()
        if self.pfpAttributes.contact == nil {
            missingPs.insert(nEvent.publicKey)
        }
        else if let c = self.pfpAttributes.contact?.contact, c.metadata_created_at == 0 {
            missingPs.insert(nEvent.publicKey)
        }
        let eventContactPs = (referencedContacts.compactMap({ contact in
            if (contact.contact?.metadata_created_at ?? 0) != 0 {
                return contact.pubkey
            }
            return nil
        }) + [nEvent.publicKey])
        
        let (contentElementsDetail, linkPreviewURLs, imageUrls) = NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags)
        self.linkPreviewURLs = linkPreviewURLs
        self.imageUrls = imageUrls
        
        self.contentElementsDetail = contentElementsDetail
        
        self.following = isFollowing(nEvent.publicKey)
        
        self.missingPs = missingPs
        
        self.content = nEvent.content
        self.isNSFW = self.hasNSFWContent()

    }
    
    private func hasNSFWContent() -> Bool {
        // event contains nsfw hashtag?
        return fastTags.first(where: { $0.0 == "t" && $0.1.lowercased() == "nsfw" }) != nil
        
        // TODO: check labels/reports
    }
    
    private static func isBlocked(pubkey:String) -> Bool {
        return Nostur.blocks().contains(pubkey)
    }
    
    
    
    
    

    
    

    
    private func rebuildContentElements() {
        bg().perform { [weak self] in
            guard let self = self else { return }
            
            let (contentElementsDetail, _, _) =  NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags)
            
            DispatchQueue.main.async { [weak self] in
                // self.objectWillChange.send() // Not needed? because this is only for things not on screen yet
                // for on screen we already use .onReceive
                // if it doesn't work we need to change let nrPost:NRPost to @ObserverdObject var nrPost:NRPost on ContentRenderer
                // and enable self.objectWillChange.send() here.
                self?.contentElementsDetail = contentElementsDetail
            }
        }
    }
}
