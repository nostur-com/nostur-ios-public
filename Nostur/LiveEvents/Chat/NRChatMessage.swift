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

    let SPAM_LIMIT_P: Int = 50
 
    static func == (lhs: NRChatMessage, rhs: NRChatMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let nEvent: NEvent
    var nxEvent: NXEvent {
        NXEvent(pubkey: nEvent.publicKey, kind: nEvent.kind.id)
    }

    public var createdAt: Date { Date(timeIntervalSince1970: TimeInterval(nEvent.createdAt.timestamp)) }
    public var created_at: Int64 { Int64(nEvent.createdAt.timestamp) }
    
    var id: NRPostID { nEvent.id }
        
    var pubkey: String { nEvent.publicKey }
        
    var content: String?
    
    var contentElementsDetail: [ContentElement] = [] // PostDetail.Kind1
    var via: String?
    
    @Published var contact: NRContact? = nil
    
    private var contactSavedSubscription: AnyCancellable?
 
    var firstE: String? // Needed for muting
      
    var missingPs: Set<String> = [] // missing or have no contact info
    var fastTags: [(String, String, String?, String?, String?)] = []
    var hashtags: Set<String> = [] // lowercased hashtags for fast hashtag blocking

    var following = false
   
    var linkPreviewURLs: [URL] = []
    var imageUrls: [URL] = []
    
    var plainTextOnly = false
    
    var anyName: String?
     
    var inWoT: Bool = false // This is just one of the inputs to determine spam or not, should have more inputs.
    
    var isNSFW: Bool = false
    
    var sats: Double?
    
    init(nEvent: NEvent) {
        self.nEvent = nEvent
        
        let fastTags: [(String, String, String?, String?, String?)] = nEvent.tags.map { ($0.type, $0.value, $0.tag[safe: 2], $0.tag[safe: 3], $0.tag[safe: 4]) }
        let fastPs: [(String, String, String?, String?, String?)] = fastTags.filter { $0.0 == "p" }
        
        let (contentElementsDetail, linkPreviewURLs, imageUrls) = NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags)
        self.linkPreviewURLs = linkPreviewURLs
        self.imageUrls = imageUrls
        
        self.contentElementsDetail = contentElementsDetail
        
        self.inWoT = WebOfTrust.shared.isAllowed(nEvent.publicKey)
        
        
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
        var missingPs = Set<String>()
        
        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: nEvent.publicKey) {
            self.contact = cachedNRContact
            anyName = cachedNRContact.contact?.anyName
            if let c = cachedNRContact.contact, c.metadata_created_at == 0 {
                missingPs.insert(nEvent.publicKey)
            }
        }
        else if let contact = Contact.contactBy(pubkey: nEvent.publicKey, context: bg()) {
            self.contact = NRContact(contact: contact)
            anyName = contact.anyName
            if contact.metadata_created_at == 0 {
                missingPs.insert(nEvent.publicKey)
            }
        }
        else {
            missingPs.insert(nEvent.publicKey)
            anyName = String(nEvent.publicKey.suffix(11))
        }
        
        self.anyName = anyName
        
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
