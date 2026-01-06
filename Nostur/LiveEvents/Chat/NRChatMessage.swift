//
//  NRChatMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/07/2024.
//

import Foundation
import Combine
import NostrEssentials

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

    var nrContact: NRContact
 
    var firstE: String? // Needed for muting
      
    var missingPs: Set<String> = [] // missing or have no contact info
    var fastTags: [FastTag] = []
    var hashtags: Set<String> = [] // lowercased hashtags for fast hashtag blocking

    var following = false
   
    var linkPreviewURLs: [URL] = []
    var galleryItems: [GalleryItem] = []
    
    var plainTextOnly = false
    
    var anyName: String {
        nrContact.anyName
    }
     
    var inWoT: Bool = false // This is just one of the inputs to determine spam or not, should have more inputs.
    
    var isNSFW: Bool = false
    
    var sats: Double?
    
    // to show success/error in chat bubble
    public var dmSendResult: [String: RecipientResult] = [:] // [pubkey: RecipientResult]
    
    public var replyToId: String?
    public var replyTo: NRChatMessage? {
        didSet { self.stopListeningForEmbeddedContent() }
    }
    
    public var quoteId: String?
    public var quotedEvent: NRChatMessage? {
        didSet { self.stopListeningForEmbeddedContent() }
    }
    
    private var embeddedContentListener: AnyCancellable?
    
    init(nEvent: NEvent, keyPair: (publicKey: String, privateKey: String)? = nil) {
        self.nEvent = nEvent
        
        let fastTags: [FastTag] = nEvent.tags.map { ($0.type, $0.value, $0.tag[safe: 2], $0.tag[safe: 3], $0.tag[safe: 4], $0.tag[safe: 5], $0.tag[safe: 6], $0.tag[safe: 7], $0.tag[safe: 8], $0.tag[safe: 9]) }
        let fastPs: [FastTag] = fastTags.filter { $0.0 == "p" }
        
        let content: String = if nEvent.kind == .legacyDirectMessage {
            if let keyPair {
                if nEvent.publicKey == keyPair.publicKey, let firstP = nEvent.firstP() {
                    Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: firstP, content: nEvent.content) ?? "(Encrypted content)"
                }
                else {
                    Keys.decryptDirectMessageContent(withPrivateKey: keyPair.privateKey, pubkey: nEvent.publicKey, content: nEvent.content) ?? "(Encrypted content)"
                }
            }
            else { convertToHieroglyphs(text: "(Encrypted content)") }
        } else { nEvent.content }
        
        let (contentElementsDetail, linkPreviewURLs, galleryItems) = NRContentElementBuilder.shared.buildElements(input: content, fastTags: fastTags, primaryColor: Themes.default.theme.primary)
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
        
        let contactsFromDb: [NRContact] = if !Thread.isMainThread { Contact.fetchByPubkeys(uncachedPtags)
                .map { NRContact.instance(of: $0.pubkey, contact: $0) }
        } else { [] }
        
        let referencedContacts = cachedContacts + contactsFromDb
        
        var missingPs = Set<String>()
    
        self.nrContact = NRContact.instance(of: nEvent.publicKey)
        if self.nrContact.metadata_created_at == 0 {
            missingPs.insert(nEvent.publicKey)
        }
        
        let eventContactPs = (referencedContacts.compactMap({ contact in
            if contact.metadata_created_at != 0 {
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
        self.loadEmbeddedContent(keyPair)
    }
    
    private func loadEmbeddedContent(_ keyPair: (publicKey: String, privateKey: String)? = nil) {
        if let replyToId = nEvent.firstE() {
            self.replyToId = replyToId
            if let replyToEvent = Event.fetchEvent(id: replyToId, context: context()) {
                self.replyTo = NRChatMessage(nEvent: replyToEvent.toNEvent(), keyPair: keyPair)
            }
        }
        if let quoteId = nEvent.tags.first(where: { $0.type == "q" })?.value {
            self.quoteId = quoteId
            if let quotedEvent = Event.fetchEvent(id: quoteId, context: context()) {
                self.quotedEvent = NRChatMessage(nEvent: quotedEvent.toNEvent(), keyPair: keyPair)
            }
        }
        
        if (self.replyToId != nil && self.replyTo == nil) || (self.quoteId != nil && self.quotedEvent == nil) {
            self.listenForEmbeddedContent(keyPair)
        }
    }
    
    private func listenForEmbeddedContent(_ keyPair: (publicKey: String, privateKey: String)? = nil) {
        guard embeddedContentListener == nil else { return }
        embeddedContentListener = Importer.shared.importedDMSub
            .filter { ($0.nEvent.id == self.replyToId) || ($0.nEvent.id == self.quoteId) }
            .sink { [weak self] dmInfo in
                guard let self else { return }
                if let replyToId = self.replyToId, self.replyTo == nil {
                    if let replyToEvent = Event.fetchEvent(id: replyToId, context: context()) {
                        self.replyTo = NRChatMessage(nEvent: replyToEvent.toNEvent(), keyPair: keyPair)
                    }
                }
                else if let quoteId = self.quoteId, self.quotedEvent == nil {
                    if let quotedEvent = Event.fetchEvent(id: quoteId, context: context()) {
                        self.quotedEvent = NRChatMessage(nEvent: quotedEvent.toNEvent(), keyPair: keyPair)
                    }
                }
            }
    }
    
    // if replyTo or quotedEvent are no longer missing, cancel subscription
    private func stopListeningForEmbeddedContent() {
        if embeddedContentListener == nil { return }
        if (self.replyToId != nil && self.replyTo != nil) || (self.quoteId != nil && self.quotedEvent != nil) {
            return
        }
        embeddedContentListener?.cancel()
        embeddedContentListener = nil
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


class RecipientResult: ObservableObject, Identifiable {
    let id: UUID
    @Published var anySuccess = false
    @Published var allFailed = false
    
    public var recipientPubkey: String
    
    public var relayResults: [String: DMSendResult] = [:]  { // [pubkey: [relay: DMSendResult]]
        didSet {
            guard !allFailed else { return }
            var failed = 0
            for (_, sendResult) in relayResults {
                if sendResult == .success {
                    Task { @MainActor in
                        anySuccess = true
                    }
                    break
                }
                else if sendResult == .timeout {
                    failed += 1
                }
            }
            if failed > 0 && failed == relayResults.count {
                Task { @MainActor in
                    allFailed = true
                }
            }
        }
    }
    
    init(recipientPubkey: String, relayResults: [String : DMSendResult]) {
        self.id = UUID()
        self.recipientPubkey = recipientPubkey
        self.relayResults = relayResults
        if relayResults.isEmpty {
            self.allFailed = true
        }
    }
}
