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
    
    var contact: NRContact?  {
        get { pfpAttributes.contact }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.pfpAttributes.contact = newValue
            }
        }
    }
    var pfpAttributes: PFPAttributes
 
    var firstE: String? // Needed for muting
      
    var missingPs: Set<String> = [] // missing or have no contact info
    var fastTags: [FastTag] = []
    var hashtags: Set<String> = [] // lowercased hashtags for fast hashtag blocking

    var following = false
   
    var linkPreviewURLs: [URL] = []
    var galleryItems: [GalleryItem] = []
    
    var plainTextOnly = false
    
    var anyName: String {
        pfpAttributes.anyName
    }
     
    var inWoT: Bool = false // This is just one of the inputs to determine spam or not, should have more inputs.
    
    var isNSFW: Bool = false
    
    var sats: Double?
    
    init(nEvent: NEvent) {
        self.nEvent = nEvent
        
        let fastTags: [FastTag] = nEvent.tags.map { ($0.type, $0.value, $0.tag[safe: 2], $0.tag[safe: 3], $0.tag[safe: 4], $0.tag[safe: 5], $0.tag[safe: 6], $0.tag[safe: 7], $0.tag[safe: 8], $0.tag[safe: 9]) }
        let fastPs: [FastTag] = fastTags.filter { $0.0 == "p" }
        
        let (contentElementsDetail, linkPreviewURLs, galleryItems) = NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags, primaryColor: Themes.default.theme.primary)
        self.linkPreviewURLs = linkPreviewURLs
        self.galleryItems = galleryItems
        
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
        let cachedContacts: [NRContact] = pTags.compactMap { NRContactCache.shared.retrieveObject(at: $0) }
        let cachedContactPubkeys = Set(cachedContacts.map { $0.pubkey })
        let uncachedPtags = pTags.filter { !cachedContactPubkeys.contains($0)  }
        
        let contactsFromDb: [NRContact] = Contact.fetchByPubkeys(uncachedPtags)
            .map { NRContact.instance(of: $0.pubkey, contact: $0) }
        
        let referencedContacts = cachedContacts + contactsFromDb
        
        var missingPs = Set<String>()
    
        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: nEvent.publicKey) {
            self.pfpAttributes = PFPAttributes(contact: cachedNRContact, pubkey: nEvent.publicKey)
            if let c = cachedNRContact.contact, c.metadata_created_at == 0 {
                missingPs.insert(nEvent.publicKey)
            }
        }
        else if let contact = Contact.fetchByPubkey(nEvent.publicKey, context: bg()) {
            self.pfpAttributes = PFPAttributes(contact: NRContact.instance(of: nEvent.publicKey, contact: contact), pubkey: nEvent.publicKey)
            if contact.metadata_created_at == 0 {
                missingPs.insert(nEvent.publicKey)
            }
        }
        else {
            self.pfpAttributes = PFPAttributes(pubkey: nEvent.publicKey)
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
        fastPs.prefix(SPAM_LIMIT_P).forEach { fastTag in
            if !eventContactPs.contains(fastTag.1) {
                missingPs.insert(fastTag.1)
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
            
            let (contentElementsDetail, _, _) =  NRContentElementBuilder.shared.buildElements(input: nEvent.content, fastTags: fastTags, primaryColor: Themes.default.theme.primary)
            
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
