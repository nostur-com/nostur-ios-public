//
//  NRPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI
import Combine

public typealias NRPostID = String

// NRPost SHOULD BE CREATED IN BACKGROUND THREAD
class NRPost: ObservableObject, Identifiable, Hashable, Equatable, IdentifiableDestination {
    
    @Published var groupedRepliesSorted: [NRPost] = []
    @Published var groupedRepliesNotWoT: [NRPost] = []
    

    // Separate ObservableObjects for view performance optimization
    var nrLiveEvent: NRLiveEvent?
    var postOrThreadAttributes: PostOrThreadAttributes
    var postRowDeletableAttributes: PostRowDeletableAttributes
    var noteRowAttributes: NoteRowAttributes
    var highlightAttributes: HighlightAttributes = HighlightAttributes()
    var replyingToAttributes: ReplyingToAttributes
    var footerAttributes: FooterAttributes
    var ownPostAttributes: OwnPostAttributes
    
    let SPAM_LIMIT_P: Int = 50
 
    static func == (lhs: NRPost, rhs: NRPost) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let createdAt: Date
    let created_at: Int64
    let ago: String
    
    let id: NRPostID
    let shortId: String
    let kind: Int64
    var kTag: String? // Note that this is string and Event.kTag is Int64
    
    let pubkey: String
    
    var subject: String?
    var content: String?
    var plainText: String = ""
    var contentElements: [ContentElement] = [] // NoteRow.Kind1
    var contentElementsDetail: [ContentElement] = [] // PostDetail.Kind1
    var via: String?
    var proxy: String?
    var comment: String? // treat as content for kind 9802
    
    var samples: [Int]? // kind 1222+1244 waveform data
    var duration: Int? // kind 1222+1244 audio length in seconds
    var audioUrl: URL? // kind 1222+1244 audio url from content
    
    var nxZap: NxZap?
    
    var contact: NRContact
    
    var replyingToUsernamesMarkDown:AttributedString? {
        get { replyingToAttributes.replyingToUsernamesMarkDown }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.replyingToAttributes.replyingToUsernamesMarkDown = newValue
            }
        }
    }
    
    private var _parentPosts: [NRPost] // access from BG only through .parentPosts
    
    var parentPosts: [NRPost] { // access from BG only
        get { _parentPosts }
        set {
            _parentPosts = newValue // Thread 1 - Data race in Nostur.NRPost.parentPosts.setter : Swift.Array<Nostur.NRPost> at 0x112075600
            DispatchQueue.main.async { [weak self] in
                self?.postOrThreadAttributes.parentPosts = newValue
            }
        }
    }
    
    private var _replies: [NRPost] = []

    var replies: [NRPost] {
        get { AppState.shared.nrPostQueue.sync { [weak self] in
            self?._replies ?? []
        } }
        set {
            AppState.shared.nrPostQueue.async(flags: .barrier) { [weak self] in
                self?._replies = newValue
            }
        }
    }
    
    private var _repliesToRoot: [NRPost] = [] {
        didSet {
            if withGroupedReplies {
                self.groupRepliesToRoot.send([])
            }
        }
    }

    var repliesToRoot: [NRPost] {
        get { AppState.shared.nrPostQueue.sync { [weak self] in
            self?._repliesToRoot ?? []
        } }
        set { AppState.shared.nrPostQueue.async(flags: .barrier) { [weak self] in
            self?._repliesToRoot = newValue
        } }
    }
    var groupedReplies = [NRPost]()
    
    let isRepost: Bool
    let isRumor: Bool // no sig and .otherId not nil means rumor. .otherId is from the outer giftwrap id

    var threadPostsCount: Int
    var isTruncated: Bool = false
    
    var replyToId: String?
    var replyToRootId: String?
    
    var _replyTo: NRPost?
    var _replyToRoot: NRPost?
    
    var firstQuoteId: String?
    
    var replyTo: NRPost? {
        get { AppState.shared.nrPostQueue.sync { [weak self] in
            self?._replyTo
        } }
        set { AppState.shared.nrPostQueue.async(flags: .barrier) { [weak self] in
            self?._replyTo = newValue
        } }
    }
    
    var replyToRoot: NRPost? {
        get { AppState.shared.nrPostQueue.sync { [weak self] in
            self?._replyToRoot
        } }
        set { AppState.shared.nrPostQueue.async(flags: .barrier) { [weak self] in
            self?._replyToRoot = newValue
        } }
    }
    
    var firstQuote: NRPost? {
        get { noteRowAttributes.firstQuote }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.noteRowAttributes.firstQuote = newValue
            }
        }
    }
  
    var firstE: String? // Needed for muting
    var deletedById: String? {
        get { postRowDeletableAttributes.deletedById }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.postRowDeletableAttributes.deletedById = newValue
            }
        }
    }
    
    var event: Event? // Only touch this in BG context!!!
    
    var missingPs: Set<String> // missing or have no contact info
    var fastTags: [FastTag] = []
    var hashtags: Set<String> = [] // lowercased hashtags for fast hashtag blocking
    
    var fileMetadata: KindFileMetadata?
    
    var blocked: Bool {
        get { postRowDeletableAttributes.blocked }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.postRowDeletableAttributes.blocked = newValue
            }
        }
    }

    
    var linkPreviewURLs: [URL] = []
    var galleryItems: [GalleryItem] = []
    var previewWeights: PreviewWeights?
    var plainTextOnly = false
    var flags: String {
        get { ownPostAttributes.flags }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.ownPostAttributes.flags = newValue
            }
        }
    }
    var dTag: String?
    var alt: String?
    var aTag: String = ""
    
    var anyName: String {
        if kind == 443 {
            let url = (fastTags.first(where: { $0.0 == "r" })?.1 ?? "Website comments")
                .replacingOccurrences(of: "https://", with: "")
            return url
        }
        else {
            return contact.anyName
        }
    }
    
    private var withFooter = true // Use false for embedded posts, where footer is not visible so we don't load/listen for likes, replies etc.
    private var withReplyTo = false
    private var withGroupedReplies = false
    private var withReplies = false // Will listen for replies from import save, and process for rendering in bg
    private var withRepliesCount = false // Will listen for replies but only for counter, no processing for rendering
    private var withParents = false
    
    private var groupRepliesToRoot = PassthroughSubject<[NRPost], Never>()
    
    let inWoT: Bool // This is just one of the inputs to determine spam or not, should have more inputs.
    let isSpam: Bool // Should use this in all views to hide or not
    let isRestricted: Bool // NIP-70: Protected Events
    
    // article/video stuff
    var eventId: String? // d tag
    var eventTitle: String?
    var eventSummary: String?
    var eventPublishedAt: Date?
    var eventImageUrl: URL?
    var eventUrl: URL?
    var mostRecentId: String?
    var blurhash: String?
    
    var isNSFW: Bool = false
    var sizeEstimate: RowSizeEstimate
    
    init(event: Event, withFooter: Bool = true, withReplyTo: Bool = false, withParents: Bool = false, withReplies: Bool = false, plainText: Bool = false, withRepliesCount: Bool = false, isPreview: Bool = false, cancellationId: UUID? = nil) {
        var isAwaiting = false
        
        self.event = event // Only touch this in BG context!!!
        self.postRowDeletableAttributes = PostRowDeletableAttributes(blocked: Self.isBlocked(pubkey: event.pubkey), deletedById: event.deletedById)
        self.id = event.id
        self.shortId = String(event.id.prefix(8))
        self.pubkey = event.pubkey
        self.kind = event.kind
        
        // Process tags
        for tag in event.fastTags {
            switch tag.0 {
            case "imeta":
                if VIDEO_TYPES.contains(Int(event.kind)), self.eventUrl == nil {
                    let imeta = parseVideoIMeta(tag)
                    if let url = imeta.url, let videoUrl = URL(string: url) {
                        self.eventUrl = videoUrl
                        self.duration = imeta.duration
                        self.blurhash = imeta.blurhash
                    }
                    if let poster = imeta.poster, let videoPoster = URL(string: poster) {
                        self.eventImageUrl = videoPoster
                    }
                    
                }
                else if let content = event.content, (event.kind == 1222 || event.kind == 1244) {
                    let (audioUrl, waveformSamples, duration) = parseVoiceMessageIMeta(tag)
                    if let audioUrl, content.contains(audioUrl.absoluteString) {
                        self.audioUrl = audioUrl
                    }
                    self.samples = waveformSamples
                    self.duration = duration
                }
            case "k":
                if self.kTag == nil {
                    self.kTag = tag.1
                }
            case "e":
                if self.firstE == nil {
                    self.firstE = tag.1
                }
            case "client":
                // Show if ["client", "Name", ""31990:..." ...]
                // Hide if ["client", ""31990:..." ..]
                if self.via == nil && tag.1.prefix(6) != "31990:" {
                    self.via = tag.1
                }
            case "proxy":
                if self.proxy == nil, let proxyValue = tag.2 {
                    self.proxy = String(format: "%@ (proxy)", proxyValue)
                }
                
            case "subject":
                if self.subject == nil {
                    self.subject = String(tag.1.prefix(255)) // 255 SPAM LIMIT
                }
                
            case "alt", "title":
                if self.alt == nil {
                    self.alt = tag.1
                }
                if self.eventTitle == nil {
                    self.eventTitle = tag.1
                }
                
            case "t":
                if !self.isNSFW {
                    if tag.1.lowercased() == "nsfw" {
                        self.isNSFW = true
                    }
                }
                
            case "content-warning": // TODO: check labels/reports
                self.isNSFW = true
                
            case "comment":
                if self.comment == nil {
                    self.comment = tag.1
                }
                
            default:
                break
            }
        }
        
        // Replace via with proxy if there is a proxy tag
        // ["proxy", "https:\/\/....", "activitypub"]
        self.via = if self.via == nil, let proxy = self.proxy {
            proxy
        }
        else {
            self.via
        }
        
        // Fallback for alt
        if ![1,6,1063,9802,30023,99999].contains(event.kind) {
            if self.alt == nil, let content = event.content, content.prefix(1) != "{" {
                self.alt = String(content.prefix(255))
            }
        }
        
        self.createdAt = event.date
        self.created_at = event.created_at
        self.ago = event.ago
        let parentPosts = withParents ? event.parentEvents.map { NRPost(event: $0) } : []
        self.postOrThreadAttributes = PostOrThreadAttributes(parentPosts: parentPosts)
        self._parentPosts = parentPosts
        
        let replies = withReplies && withFooter ? event.replies.map { NRPost(event: $0) } : []
        self._replies = replies
        self.ownPostAttributes = OwnPostAttributes(id: event.id, isOwnPost: AccountsState.shared.bgFullAccountPubkeys.contains(pubkey), relays: event.relays, cancellationId: cancellationId, flags: event.flags)
        
        if withReplies && withFooter {
            self.footerAttributes = FooterAttributes(replyPFPs: Array(_replies.compactMap { reply in
                return followingPFP(reply.pubkey)
            }
            .uniqued(on: ({ $0 }))
            .prefix(8)), event: event, withFooter: withFooter)
        }
        else {
            self.footerAttributes = FooterAttributes(event: event, withFooter: withFooter)
        }
        
        self._repliesToRoot = []
        self.threadPostsCount = 1 + event.parentEvents.count
        self.isRepost = event.kind == 6 || (event.kind == 1 && event.content == "#[0]" && event.firstE() != nil)
        self.isRumor = event.otherId != nil && event.sig == nil
        
        self.firstQuoteId = event.firstQuoteId

        if let firstQuoteId = event.firstQuoteId, let firstQuote = Event.fetchEvent(id: firstQuoteId, context: bg()) {
            self.noteRowAttributes = NoteRowAttributes(firstQuote: NRPost(event: firstQuote, withFooter: withFooter && event.kind == 6, withReplies: withReplies, withRepliesCount: withRepliesCount))
        }
        else if !isAwaiting && event.firstQuoteId != nil {
            self.noteRowAttributes = NoteRowAttributes()
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.005c"); isAwaiting = true
        }
        else {
            self.noteRowAttributes = NoteRowAttributes()
        }
        
        if let replyingToMarkdown = NRReplyingToBuilder.shared.replyingToUsernamesMarkDownString(event) {
            self.replyingToAttributes = ReplyingToAttributes(replyingToUsernamesMarkDown: try? AttributedString(markdown: replyingToMarkdown))
        }
        else {
            self.replyingToAttributes = ReplyingToAttributes()
        }
        
        self.fastTags = event.fastTags
        self.plainText = NRTextParser.shared.copyPasteText(fastTags: fastTags, event: event, text: event.content ?? "").text // TODO: prepend "comment" if highlight
        self.withParents = withParents
        self.withReplies = withReplies
        self.withReplyTo = withReplyTo
        self.withRepliesCount = withRepliesCount
        self.plainTextOnly = plainText
        self.inWoT = event.inWoT
        self.isSpam = event.isSpam
        if event.isSpam {
            ConnectionPool.shared.notInWoTcount += 1
        }
        self.aTag = event.aTag
        self.hashtags = Set(fastTags.filter { $0.0 == "t" }.compactMap({ fastTag in
            if (fastTag.1 == "") { return nil }
            return fastTag.1.lowercased()
        }))
        
        
        self.isRestricted = event.isRestricted
        
        let pTags = event.fastPs.map { $0.1 }
        let cachedContacts = pTags.compactMap { NRContactCache.shared.retrieveObject(at: $0) }
        let cachedContactPubkeys = Set(cachedContacts.map { $0.pubkey })
        let uncachedPtags = pTags.filter { !cachedContactPubkeys.contains($0)  }
        
        let contactsFromDb = Contact.fetchByPubkeys(uncachedPtags).map { contact in
            return NRContact.instance(of: contact.pubkey, contact: contact)
        }
        
        let referencedContacts = cachedContacts + contactsFromDb
        
        self.contact = NRContact.instance(of: pubkey)

        var missingPs = Set<String>()
        if contact.metadata_created_at == 0 {
            missingPs.insert(event.pubkey)
        }
        let eventContactPs = (referencedContacts.compactMap({ contact in
            if contact.metadata_created_at != 0 {
                return contact.pubkey
            }
            return nil
        }) + [event.pubkey])
        
        // Some clients put P in kind 6. Ignore that because the contacts are in the reposted post, not in the kind 6.
        // TODO: Should only fetch if the Ps are going to be on screen. Could be just for notifications.
        if kind != 6 {
            event.fastPs.prefix(SPAM_LIMIT_P).forEach { fastTag in
                if !eventContactPs.contains(fastTag.1) {
                    missingPs.insert(fastTag.1)
                }
            }
        }

        // Start doing kind specific stuff here (TODO)
        
        if kind >= 30000 && kind < 40000 {
            dTag = event.dTag
        }
        
        switch kind {
        case 1222,1244:
            // self.audioUrl should already be set from .init() (Process tags)
            guard self.audioUrl == nil, let urlContent = event.content, !urlContent.isEmpty, let url = URL(string: urlContent) else { break }
            // if its somehow not set (from init, which checks imeta and matching url in .content). We can try again here our original method (just .content)
            self.audioUrl = url
            // Also make text + url in content work if first imeta url matches ANY url in .content
        case 1063:
            self.fileMetadata = getKindFileMetadata(event: event)

        case 9735:
            guard let zapFrom = event.zapFromRequest else { break }
            self.nxZap = NxZap(id: event.id,
                         sats: event.naiveSats,
                         receiptPubkey: event.pubkey,
                         fromPubkey: zapFrom.pubkey,
                         nrZapFrom: NRPost(event: zapFrom,
                                           withFooter: false,
                                           withReplyTo: false,
                                           withParents: false,
                                           withReplies: false,
                                           plainText: false,
                                           withRepliesCount: false
                                          ),
                         verified: event.flags != "zpk_mismatch_event"
                        )
            
        case 9802:
            let highlightUrl = event.fastTags.first(where: { $0.0 == "r" } )?.1
            
            // take first p and prioritize author if multiple p
            let highlightAuthorPubkey: String? = event.fastPs
                .sorted(by: { $0.3 == "author" &&  $1.3 != "author" })
                .first?.1
            
            let highlightContact: NRContact? = if let highlightAuthorPubkey {
                NRContact.instance(of: highlightAuthorPubkey)
            }
            else {
                nil
            }
            
            if let highlightContact, highlightContact.metadata_created_at == 0 {
                missingPs.insert(highlightContact.pubkey)
            }
            self.highlightAttributes = HighlightAttributes(contact: highlightContact, authorPubkey: highlightAuthorPubkey, url: highlightUrl)
        case 30000, 39089:
            eventTitle = event.eventTitle
            
        case 30023, 30311:
            eventId = event.eventId
            eventTitle = event.eventTitle
            eventSummary = event.eventSummary
            eventPublishedAt = event.eventPublishedAt
            if let eventImageUrlString = (event.eventImage ?? event.eventThumb), let eventImageUrl = URL(string: eventImageUrlString.replacingOccurrences(of: "http://", with: "https://")) {
                self.eventImageUrl = eventImageUrl
            }
            if let eventUrlString = event.eventUrl, let eventUrl = URL(string: eventUrlString) {
                self.eventUrl = eventUrl
            }
            mostRecentId = event.mostRecentId
            
            if event.kind == 30311 {
                self.nrLiveEvent = NRLiveEvent(event: event)
            }
            
        case 21, 22, 34235, 34236:
            eventId = event.eventId
            eventTitle = event.eventTitle
            eventSummary = event.eventSummary
            eventPublishedAt = event.eventPublishedAt
            if let eventImageUrlString = (event.eventImage ?? event.eventThumb), let eventImageUrl = URL(string: eventImageUrlString.replacingOccurrences(of: "http://", with: "https://")) {
                self.eventImageUrl = eventImageUrl
            }
            if self.eventUrl == nil, let eventUrlString = event.eventUrl, let eventUrl = URL(string: eventUrlString) {
                self.eventUrl = eventUrl
            }
            mostRecentId = event.mostRecentId
            
            if event.kind == 30311 {
                self.nrLiveEvent = NRLiveEvent(event: event)
            }
            
        default:
            break
        }
        
        if !plainText { // plainText is actually plainTextOnly, for rendering in muted spam stuff
            
            let input = if kind == 9802 {
                self.comment ?? ""
            }
            else {
                event.noteTextPrepared
            }
            
            let (contentElementsDetail, linkPreviewURLs, galleryItems) = (kind == 30023) ? NRContentElementBuilder.shared.buildArticleElements(event)
                : NRContentElementBuilder.shared.buildElements(
                    input: input,
                    fastTags: event.fastTags,
                    event: event,
                    primaryColor: Themes.default.theme.primary,
                    previewImages: event.previewImages,
                    previewVideos: event.previewVideos,
                    isPreviewContext: isPreview // render without nostr: or not (in preview no, to discourage)
            )
            self.linkPreviewURLs = linkPreviewURLs
            self.galleryItems = galleryItems
            
            self.contentElementsDetail = contentElementsDetail
            let (contentElements, previewWeights) = filteredForPreview(contentElementsDetail)
            self.contentElements = contentElements
            
            for index in self.contentElements.indices {
                switch self.contentElements[index] {
                case .nevent1(let identifier):
                    guard let id = identifier.eventId else { continue }
                    guard let event = Event.fetchEvent(id: id, context: bg()) else { continue }
                    self.contentElements[index] = ContentElement.nrPost(NRPost(event: event))
                case .note1(let noteId):
                    guard let id = hex(noteId) else { continue }
                    guard let event = Event.fetchEvent(id: id, context: bg()) else { continue }
                    self.contentElements[index] = ContentElement.nrPost(NRPost(event: event))
                case .noteHex(let id):
                    guard let event = Event.fetchEvent(id: id, context: bg()) else { continue }
                    self.contentElements[index] = ContentElement.nrPost(NRPost(event: event))
                default:
                    continue
                }
            }
            
            self.previewWeights = previewWeights
        }
        
        self.sizeEstimate = previewWeights?.sizeEstimate ?? .small
        
        self.missingPs = missingPs
        if !isAwaiting && !self.missingPs.isEmpty {
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.002 - missingPs: \(missingPs.count)"); isAwaiting = true
        }
        
        self.replyToId = event.replyToId
        if withReplyTo, let replyTo = event.replyTo {
            self.replyTo = NRPost(event: replyTo)
        }
        else if !isAwaiting && withReplyTo && event.replyToId != nil {
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.003"); isAwaiting = true
        }
        
        self.replyToRootId = event.replyToRootId
        if withReplyTo, let replyToRoot = event.replyToRoot {
            self.replyToRoot = NRPost(event: replyToRoot)
        }
        else if !isAwaiting && withReplyTo && event.replyToRootId != nil {
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.004"); isAwaiting = true
        }
        
        if let content = event.content {
            self.content = content
        }
        
        setupSubscriptions()
    }
    
    private static func isBlocked(pubkey:String) -> Bool {
        return Nostur.blocks().contains(pubkey)
    }
    
    private var profileUpdatedSubscription: AnyCancellable?
    private var postDeletedSubscription: AnyCancellable?
    private var repliesSubscription: AnyCancellable?
    private var repliesCountSubscription: AnyCancellable?
    private var relationSubscription: AnyCancellable?
    private var updateNRPostSubscription: AnyCancellable?
    private var unpublishSubscription: AnyCancellable?
    private var publishSubscription: AnyCancellable?
    private var repliesToRootSubscription: AnyCancellable?
    private var groupRepliesToRootSubscription: AnyCancellable?
    
    private func setupSubscriptions() {
        // Don't listen if there is no need to listen (performance?)
        
        if !missingPs.isEmpty {
            profileUpdatedListener()
        }
        
        if deletedById == nil {
            postDeletedListener()
        }

        if withReplies {
            repliesListener()
        }
        else if withRepliesCount {
            repliesCountListener()
        }
        
        
        if isRepost || withReplyTo || (firstQuoteId != nil && firstQuote == nil) {
            relationListener()
        }
        
        updateNRPostListener()
        unpublishListener()
        
        groupRepliesToRootSubscription = groupRepliesToRoot
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] nrPosts in
                guard let self = self else { return }
                self._groupRepliesToRoot(nrPosts)
            }
    }
    
    
    
    private func updateNRPostListener() {
        guard updateNRPostSubscription == nil else { return }
        let id = id
        updateNRPostSubscription = ViewUpdates.shared.updateNRPost
            .filter { $0.id == id }
            .sink { [weak self] event in
                guard let self else { return }
                
                let relaysString = event.relays
                let relays = Set(relaysString.split(separator: " ").map { String($0) }).filter { $0 != "" } 
                let flags = event.flags
                let cancellationId = event.cancellationId

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.ownPostAttributes.objectWillChange.send()
                    self.ownPostAttributes.relays = relays.union(self.ownPostAttributes.relays)
                    self.ownPostAttributes.flags = flags
                    self.ownPostAttributes.cancellationId = cancellationId
                    
                    self.footerAttributes.objectWillChange.send()
                    self.footerAttributes.relays = relays.union(self.footerAttributes.relays)
                }
            }
    }
    
    private func unpublishListener() {
        guard unpublishSubscription == nil else { return }

        // the undo can be in the replies, so don't check for own account keys yet
        unpublishSubscription = receiveNotification(.unpublishedNRPost)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard self.withGroupedReplies else { return }
                let nrPost = notification.object as! NRPost
                guard replies.contains(where: { $0.id == nrPost.id }) || repliesToRoot.contains(where: { $0.id == nrPost.id })
                else { return }
                self.loadGroupedReplies()
            }
        
        
        // Only for our accounts, handle undo of this post.
        guard AccountsState.shared.bgFullAccountPubkeys.contains(self.pubkey) else { return }
        
        publishSubscription = receiveNotification(.publishingEvent)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let eventId = notification.object as! String
                guard eventId == self.id else { return }
                
                DispatchQueue.main.async { [weak self] in
                    self?.ownPostAttributes.objectWillChange.send()
                    self?.ownPostAttributes.cancellationId = nil
                }
            }
    }
    
    // For rerendering ReplyingToFragment, or setting .contact
    // Or Rebuilding content elements for mentions in text
    private func profileUpdatedListener() {
        guard profileUpdatedSubscription == nil else { return }
        // Rerender ReplyingToFragment when the new contact is saved (only if we replyToId is set)
        // Rerender content elements also for mentions in text
        profileUpdatedSubscription = ViewUpdates.shared.profileUpdates
            .filter({ [weak self] profileInfo in
                guard let self = self else { return false }
                return self.missingPs.contains(profileInfo.pubkey)
            })
            .sink { [weak self] profileInfo in
                guard let self = self else { return }
                self.missingPs.remove(profileInfo.pubkey)
                
                if self.kind != 6 {
                    if self.replyToId != nil {
                        self.rerenderReplyingToFragment()
                    }
                    // TODO: no need to rebuild if p is not in text/content/comment
                    self.rebuildContentElements()
                    
                    if self.kind == 9802 && self.highlightAttributes.authorPubkey == pubkey {
                        bg().perform {
                            let nrContact = NRContact.instance(of: self.pubkey)
                            DispatchQueue.main.async { [weak self] in
                                self?.highlightAttributes.objectWillChange.send()
                                self?.highlightAttributes.contact = nrContact
                            }
                        }
                    }
                }
                
                if self.missingPs.isEmpty {
                    profileUpdatedSubscription?.cancel()
                    profileUpdatedSubscription = nil
                }
            }
    }

    
    private func rebuildContentElements() {
        bg().perform { [weak self] in
            guard let self = self, let event = event else { return }
            
            let input = if kind == 9802 {
                self.comment ?? ""
            }
            else {
                event.noteTextPrepared
            }
            
            let (contentElementsDetail, _, _) = (kind == 30023) ? NRContentElementBuilder.shared.buildArticleElements(event)
                : NRContentElementBuilder.shared.buildElements(
                    input: input,
                    fastTags: event.fastTags,
                    event: event,
                    primaryColor: Themes.default.theme.primary,
                    previewImages: event.previewImages,
                    previewVideos: event.previewVideos,
                    isPreviewContext: false
            )
            let (contentElements, _) = filteredForPreview(contentElementsDetail)
            
            DispatchQueue.main.async { [weak self] in
                // self.objectWillChange.send() // Not needed? because this is only for things not on screen yet
                // for on screen we already use .onReceive
                // if it doesn't work we need to change let nrPost:NRPost to @ObserverdObject var nrPost:NRPost on ContentRenderer
                // and enable self.objectWillChange.send() here.
                self?.contentElementsDetail = contentElementsDetail
                self?.contentElements = contentElements
            }
        }
    }
    private func rerenderReplyingToFragment() {
        bg().perform { [weak self] in
            guard let self = self, let event = event else { return }
            if let replyingToMarkdown = NRReplyingToBuilder.shared.replyingToUsernamesMarkDownString(event) {
                let md = try? AttributedString(markdown: replyingToMarkdown)
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                    self?.replyingToUsernamesMarkDown = md
                }
            }
        }
    }
    
    private func postDeletedListener() {
        guard postDeletedSubscription == nil else { return }
        let id = id
        postDeletedSubscription = ViewUpdates.shared.postDeleted
            .filter { $0.toDeleteId == id }
            .receive(on: RunLoop.main)
            .sink { [weak self] deletion in
                guard let self = self else { return }
                self.deletedById = deletion.deletedById
            }
    }
    
    private func relationListener() {
        guard relationSubscription == nil else { return }
        
        let id = id
        relationSubscription = ViewUpdates.shared.eventRelationUpdate
            .filter { $0.id == id }
            .sink { [weak self] relationUpdate in
                guard let self else { return }
                switch relationUpdate.relationType {
                case .replyTo:
                    let nrReplyTo = NRPost(event: relationUpdate.event, withReplyTo: true)
                    DispatchQueue.main.async { [weak self] in
                        self?.objectWillChange.send()
                        self?.replyTo = nrReplyTo
                        // self.loadReplyTo() // need this??
                    }
                case .replyToRoot:
                    let nrReplyToRoot = NRPost(event: relationUpdate.event, withReplyTo: true)
                    DispatchQueue.main.async { [weak self] in
                        self?.objectWillChange.send()
                        self?.replyToRoot = nrReplyToRoot
                        // self.loadReplyTo() // need this??
                    }
                case .firstQuote:
                    let nrFirstQuote = NRPost(event: relationUpdate.event, withReplyTo: true, withReplies: self.withReplies)
                    DispatchQueue.main.async { [weak self] in
                        self?.objectWillChange.send()
                        self?.noteRowAttributes.firstQuote = nrFirstQuote
                    }
                case .replyToRootInverse:
                    let nrReply = NRPost(event: relationUpdate.event, withReplyTo: false, withParents: false, withReplies: false, plainText: false)
                    self.repliesToRoot.append(nrReply)
                    self.groupRepliesToRoot.send(self.replies)
                }
            }
    }
    
    private func repliesListener() {
        guard repliesSubscription == nil else { return }

        let id = self.id
        repliesSubscription = ViewUpdates.shared.repliesUpdated
            .filter { $0.id == id }
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] change in
                let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
                bg().perform { [weak self] in
                    guard let self else { return }
                    let nrReplies = change.replies
                            .filter { !blocks().contains($0.pubkey) }
                            .map { event in
                                let nrPost = NRPost(event: event, cancellationId: cancellationIds[event.id])
                                return nrPost
                            }
  
                    if (self.withGroupedReplies) {
                        self.groupRepliesToRoot.send(nrReplies)
                    }
                    else {
                        let replyPFPs = nrReplies
                            .compactMap { reply in
                                return followingPFP(reply.pubkey)
                            }
                            .uniqued(on: ({ $0 }))
                            .prefix(8)
                        
                        self.event?.repliesCount = Int64(nrReplies.count) // Fix wrong count in db
                        DispatchQueue.main.async { [weak self] in
                            self?.objectWillChange.send()
                            self?.replies = nrReplies
                            
                            self?.footerAttributes.objectWillChange.send()
                            self?.footerAttributes.repliesCount = Int64(nrReplies.count)
                            self?.footerAttributes.replyPFPs = Array(replyPFPs)
                        }
                    }
                }
            }
    }
    
    // Same as repliesListener but only for counts
    // TODO: NO NEED? ALREADY PART OF ViewUpdates.shared.eventStatChanged ??
    private func repliesCountListener() {
        guard repliesSubscription == nil else { return } // Skip if we already have repliesListener, which makes repliesCountListener not needed
        guard repliesCountSubscription == nil else { return }
        guard !withReplies else { return }

        let id = self.id
        repliesCountSubscription = ViewUpdates.shared.repliesUpdated
            .filter { $0.id == id }
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] change in
                self?.footerAttributes.objectWillChange.send()
                self?.footerAttributes.repliesCount = Int64(change.replies.count)
            }
    }
    
    // TODO: 103.00 ms    0.9%    0 s          closure #2 in NRPost.loadReplies()
    private func loadReplies() {
        if (!self.withReplies) {
            self.withReplies = true
            repliesListener()
        }
        let ctx = bg()
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        ctx.perform { [weak self] in
            guard let self else { return }
            
            let fr = Event.fetchRequest()
            let afterCreatedAt = self.created_at - 7200 // allow some time mismatch (2 hours)
            fr.predicate = NSPredicate(format: "created_at > %i AND kind IN {1,1111,1244} AND replyToId == %@ AND NOT pubkey IN %@", afterCreatedAt, String(self.id), blocks()) // _PFManagedObject_coerceValueForKeyWithDescription + 1472 (NSManagedObject.m:0) - Maybe fix with String(self.id)
            
            let nrReplies = (self.event?.replies ?? [])
                .filter { !blocks().contains($0.pubkey) }
                .map { NRPost(event: $0, cancellationId: cancellationIds[$0.id]) }
            self.event?.repliesCount = Int64(nrReplies.count) // Fix wrong count in db
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                
                if self.replies.count != nrReplies.count  {
                    self.objectWillChange.send()
                    self.replies = nrReplies
                }
                    
                if self.footerAttributes.repliesCount != Int64(nrReplies.count) {
                    self.footerAttributes.objectWillChange.send()
                    self.footerAttributes.repliesCount = Int64(nrReplies.count)
                }
            }
        }
    }
    
    public func loadReplyTo() {
        if (!self.withReplyTo) {
            self.withReplyTo = true
            relationListener()
        }
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard self.replyTo == nil else { return }
            guard let replyToId = self.replyToId else { return }
            
            if let replyTo = Event.fetchEvent(id: replyToId, context: bg()) {
                let nrReplyTo = NRPost(event: replyTo, withReplyTo: true)
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                    self?.replyTo = nrReplyTo
                }
            }
        }
    }
    
    @MainActor public func loadParents() {
        let beforeThreadPostsCount = self.threadPostsCount
        bg().perform { [weak self] in
            guard let self, let event = self.event else { return }
            guard !self.withParents else { return }
            self.withParents = true
            
            let parents = Event.getParentEvents(event)//, until:self.id)
            let parentPosts = parents.map { NRPost(event: $0) }
            let threadPostsCount = 1 + event.parentEvents.count
            
            guard beforeThreadPostsCount != threadPostsCount else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
                self?.parentPosts = parentPosts
                self?.threadPostsCount = threadPostsCount
            }
        }
    }
    
    @MainActor public func like(_ reactionContent: String = "+", uuid: UUID) -> NEvent? {
        self.footerAttributes.objectWillChange.send()
        self.footerAttributes.ourReactions.insert(reactionContent)
        sendNotification(.postAction, PostActionNotification(type: .reacted(uuid, reactionContent), eventId: self.id))
        if let accountCache = accountCache() {
            accountCache.addReaction(self.id, reactionType: reactionContent)
        }
        return EventMessageBuilder.makeReactionEvent(reactingToId: id, reactingToPubkey: pubkey, reactionContent: reactionContent)
    }
    
    @MainActor public func unlike(_ reactionContent: String = "+") {
        self.footerAttributes.objectWillChange.send()
        self.footerAttributes.ourReactions.remove(reactionContent)
        sendNotification(.postAction, PostActionNotification(type: .unreacted(reactionContent), eventId: self.id))
        if let accountCache = accountCache() {
            accountCache.removeReaction(self.id, reactionType: reactionContent)
        }
    }
    
    @MainActor public func unpublish() {
        guard let cancellationId = ownPostAttributes.cancellationId else { return }
        _ = Unpublisher.shared.cancel(cancellationId)
        self.ownPostAttributes.objectWillChange.send()
        self.ownPostAttributes.cancellationId = nil
        bg().perform { [weak self] in
            guard let self, let event = self.event else { return }
            bg().delete(event)
            DataProvider.shared().saveToDiskNow(.bgContext)
            DispatchQueue.main.async {
                sendNotification(.unpublishedNRPost, self)
            }
            if let accountCache = accountCache(), accountCache.pubkey == self.pubkey {
                if Set([1,1111,1244]).contains(self.kind), let replyToId = self.replyToId {
                    accountCache.removeRepliedTo(replyToId)
                    sendNotification(.postAction, PostActionNotification(type: .unreplied, eventId: replyToId))
                }
            }
        }
    }
    
    @MainActor
    public func undelete() {
        self.objectWillChange.send()
        self.postRowDeletableAttributes.objectWillChange.send()
        self.postRowDeletableAttributes.deletedById = nil
    }
    
    @MainActor public func sendNow() {
        guard let cancellationId = ownPostAttributes.cancellationId else { return }
        let didSend = Unpublisher.shared.sendNow(cancellationId)
        self.ownPostAttributes.objectWillChange.send()
        self.ownPostAttributes.cancellationId = nil
        self.ownPostAttributes.flags = ""
        
        if !didSend {
            L.og.info("🔴🔴 Send now failed")
        }
    }
    @MainActor public func unblockFirstQuote() {
        guard firstQuote != nil else { return }
        self.objectWillChange.send()
        self.noteRowAttributes.objectWillChange.send()
        self.noteRowAttributes.firstQuote?.objectWillChange.send()
        self.noteRowAttributes.firstQuote?.blocked = false
        self.firstQuote!.objectWillChange.send()
        self.firstQuote!.blocked = false
    }
    
    private var renderedReplyIds: Set<NRPostID> = []
    
    deinit {
        profileUpdatedSubscription?.cancel()
        postDeletedSubscription?.cancel()
        repliesSubscription?.cancel()
        repliesCountSubscription?.cancel()
        relationSubscription?.cancel()
        updateNRPostSubscription?.cancel()
        unpublishSubscription?.cancel()
        publishSubscription?.cancel()
        repliesToRootSubscription?.cancel()
        groupRepliesToRootSubscription?.cancel()
    }
}

extension NRPost { // Helpers for grouped replies
    
    // To make repliesSorted work we need repliesToRoot first (.loadRepliesToRoot())
    func sortGroupedReplies(_ nrPosts: [NRPost]) -> [NRPost] { // Read from bottom to top.
        
        let followingPubkeys = AccountsState.shared.loggedInAccount?.followingPublicKeys ?? []
        
        if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
            return nrPosts
                // 4. Everything else last, newest at bottom
                .sorted(by: { $0.created_at < $1.created_at })
                // 3. People you follow third
                .sorted(by: { followingPubkeys.contains($0.pubkey) && !followingPubkeys.contains($1.pubkey) })
                // 2. Replies replied by author second
                .sorted(by: {
                    ($0.pubkey == self.pubkey) &&
                    ($1.pubkey != self.pubkey)
                })
                // 1. Own direct replies first
                .sorted(by: {
                    ($0.pubkey == self.pubkey && $0.replyToId == self.id) &&
                    ($1.pubkey != self.pubkey || $1.replyToId != self.id)
                })
        }
        
        // With WoT enabled with add filter nr 5.
        return nrPosts
            // 5. People outside WoT last
            .filter { $0.inWoT || AccountsState.shared.bgAccountPubkeys.contains($0.pubkey) || $0.pubkey == self.pubkey }
        
            // 4. Everything else in WoT last, newest at bottom
            .sorted(by: { $0.created_at < $1.created_at })
            // 3. People you follow third
            .sorted(by: { followingPubkeys.contains($0.pubkey) && !followingPubkeys.contains($1.pubkey) })
            // 2. Replies replied by author second
            .sorted(by: {
                ($0.pubkey == self.pubkey) &&
                ($1.pubkey != self.pubkey)
            })
            // 1. Own direct replies first
            .sorted(by: {
                ($0.pubkey == self.pubkey && $0.replyToId == self.id) &&
                ($1.pubkey != self.pubkey || $1.replyToId != self.id)
            })
    }
    
    func sortGroupedRepliesNotWoT(_ nrPosts:[NRPost]) -> [NRPost] { // Read from bottom to top.
        return nrPosts
            .filter { !$0.inWoT && !AccountsState.shared.bgAccountPubkeys.contains($0.pubkey) && $0.pubkey != self.pubkey }
            .sorted(by: { $0.created_at < $1.created_at })
    }
    
    // TODO: 79.00 ms    0.7%    0 s          closure #2 in NRPost.loadGroupedReplies()
    public func loadGroupedReplies() {
        self.loadReplies()
        if (!self.withGroupedReplies) {
            self.withGroupedReplies = true
            repliesToRootListener()
        }
        let ctx = bg()
        
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        ctx.perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            let afterCreatedAt = self.created_at - 7200 // allow some time mismatch (2 hours)
            if let replyToRootId = self.replyToRootId { // We are not root, so load replies for actual root instead
                fr.predicate = NSPredicate(format: "created_at > %i AND replyToRootId = %@ AND kind IN {1,1111,1244} AND NOT pubkey IN %@", afterCreatedAt, replyToRootId, blocks())
            }
            else {
                fr.predicate = NSPredicate(format: "created_at > %i AND replyToRootId = %@ AND kind IN {1,1111,1244} AND NOT pubkey IN %@", afterCreatedAt, self.id, blocks())
            }
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true )]
            let repliesToRoot = (try? ctx.fetch(fr)) ?? []
            for reply in repliesToRoot { // Add to queue because some may be missing .replyTo
                EventRelationsQueue.shared.addAwaitingEvent(reply, debugInfo: "reply in .repliesToRoot")
            }
            let nrRepliesToRoot = repliesToRoot
                .filter { !AppState.shared.bgAppState.blockedPubkeys.contains($0.pubkey) }
                .map { event in
                    let nrPost = NRPost(event: event, withReplyTo: false, withParents: false, withReplies: false, plainText: false, cancellationId: cancellationIds[event.id])
                    return nrPost
                } // Don't load replyTo/parents here, we do it in groupRepliesToRoot()
            self.repliesToRoot = nrRepliesToRoot
        }
    }
    
    private func repliesToRootListener() {
        guard repliesToRootSubscription == nil else { return }

        let id = self.id
        repliesToRootSubscription = ViewUpdates.shared.eventRelationUpdate
            .filter { $0.id == id && $0.relationType == .replyToRootInverse }
//            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] relation in
                let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
                guard let self else { return }
                
                let nrReply = NRPost(event: relation.event, withReplyTo: false, withParents: false, withReplies: false, plainText: false, cancellationId: cancellationIds[relation.event.id]) // Don't load replyTo/parents here, we do it in groupRepliesToRoot()
                self.repliesToRoot.append(nrReply)
                self.groupRepliesToRoot.send(self.replies)
            }
    }
    
    var repliesToLeaf: [NRPost] {
        // if we are not root we cannot use replyToRootId
        // we need only the replies under our leaf id
        // so we have to traverse manually:
        
        // we just start from a leaf and traverse up, if we hit our self.id its ours,
        // else it will go up to the actual root and we dont need it
        
        var ourReplies: [NRPost] = []
        for post in repliesToRoot {
            guard let event = post.event else { continue }
            if traversesUpToThisPost(event) {
                ourReplies.append(post)
            }
        }
        return ourReplies
    }
    
    private func traversesUpToThisPost(_ event: Event) -> Bool {
        var currentEvent: Event? = event
        while currentEvent != nil {
            if let replyToId = currentEvent?.replyToId, replyToId == self.id {
                return true
            }
            currentEvent = currentEvent?.replyTo
        }
        return false
    }
    
    private func _groupRepliesToRoot(_ newReplies: [NRPost]) {
        bg().perform { [weak self] in
            guard let self else { return }
            renderedReplyIds.removeAll()
            let replies = (newReplies.isEmpty ? self.replies : newReplies)
            // Load parents/replyTo
            let groupedThreads = (replies + (self.replyToRootId != nil ? self.repliesToLeaf : self.repliesToRoot))
                .uniqued(on: { $0.id })
                .filter({ nrPost in
                    return !AppState.shared.bgAppState.blockedPubkeys.contains(nrPost.pubkey)
                })
                .filter { // Only take eventual replies by author, or direct replies to root by others
                    $0.pubkey == self.pubkey ||
                    $0.replyToId == self.id
                }
                .map { reply in
                    // use until:self.id so we don't render duplicates
                    if let replyEvent = reply.event {
                        replyEvent.parentEvents = Event.getParentEvents(replyEvent, until: self.id)
                        reply.parentPosts = replyEvent.parentEvents.map { NRPost(event: $0) }
                        reply.threadPostsCount = 1 + replyEvent.parentEvents.count
                    }

//                    if let replyTo = reply.event.replyTo__ { // TODO: NEED THIS OR NO?
//                        reply.replyTo = NRPost(event: replyTo)
//                    }
                    return reply
                }
            
            // Dictionary to store unique items with highest values
            var uniqueThreads = [NRPostID: NRPost]()
            

            for thread in groupedThreads {
                if let replyToId = thread.replyToId, replyToId == self.id {
                    // replying to root, but could be rendered also as parent in one of the threads,
                    // so skip and include in 2nd pass after we checked if its not rendered already
                    continue
                }
                else if let replyToRootId = thread.replyToRootId, thread.replyToId == nil, replyToRootId == self.id {
                    // replying to root, but could be rendered also as parent in one of the threads,
                    // so skip and include in 2nd pass after we checked if its not rendered already
                    continue
                }
                
                let firstId = thread.event?.parentEvents.first?.id ?? thread.id
                if let existingThread = uniqueThreads[firstId] {
                    // TODO:
                    // if we have a forked thread, then both will have the same firstId
                    // so keep the longest, and store the shorter one with a new firstId (the last common post on both forks)
                    if thread.threadPostsCount > existingThread.threadPostsCount {
                        uniqueThreads[firstId] = thread
                    }
                } else {
                    uniqueThreads[firstId] = thread
                }
            }
            
            renderedReplyIds = Set(uniqueThreads.keys).union(uniqueThreads.values.reduce(Set<NRPostID>(), { partialResult, nrPost in
                return partialResult.union(
                    Set(
                        nrPost.event?.parentEvents.map { $0.id } ?? []
                    )
                )
            }))
            
            // Second pass
            // Include the direct replies that have not been rendered yet in other threads (renderedIds)
            for thread in groupedThreads {
                if let replyToId = thread.replyToId, replyToId == self.id, !renderedReplyIds.contains(thread.id) {
                    // direct reply
                    uniqueThreads[thread.id] = thread
                    renderedReplyIds.insert(thread.id)
                }
                else if let replyToRootId = thread.replyToRootId, thread.replyToId == nil, replyToRootId == self.id, !renderedReplyIds.contains(thread.id) {
                    // direct reply
                    uniqueThreads[thread.id] = thread
                    renderedReplyIds.insert(thread.id)
                }
            }

            // Retrieve the unique items with highest values
            let groupedReplies = Array(uniqueThreads.values)
            let groupedRepliesSorted = Array(self.sortGroupedReplies(groupedReplies).prefix(50))
            let groupedRepliesNotWoT = Array(self.sortGroupedRepliesNotWoT(groupedReplies).prefix(50))
            
            self.event?.repliesCount = Int64(replies.count) // Fix wrong count in db
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.replies = replies
                self.groupedRepliesSorted = groupedRepliesSorted
                self.groupedRepliesNotWoT = groupedRepliesNotWoT
                self.footerAttributes.objectWillChange.send()
                self.footerAttributes.repliesCount = Int64(replies.count)
            }
        }
    }
}



func getKindFileMetadata(event: Event) -> KindFileMetadata {
    return KindFileMetadata(
        url: event.fastTags.first(where: { $0.0 == "url" })?.1 ?? "",
        m: event.fastTags.first(where: { $0.0 == "m" })?.1,
        hash: event.fastTags.first(where: { $0.0 == "hash" })?.1,
        dim: event.fastTags.first(where: { $0.0 == "dim" })?.1,
        blurhash: event.fastTags.first(where: { $0.0 == "blurhash" })?.1
    )
}


// Has some subclass-ObservableObjects to isolate rerendering to specific view attributes:
// PostOrThreadAttributes, PostRowDeletableAttributes, NoteRowAttributes

class PostOrThreadAttributes: ObservableObject {
    @Published var parentPosts: [NRPost] = []
    
    init(parentPosts: [NRPost] = []) {
        self.parentPosts = parentPosts
    }
}

class PostRowDeletableAttributes: ObservableObject {
    @Published var blocked = false
    @Published var deletedById: String? = nil

    init(blocked: Bool = false, deletedById: String? = nil) {
        self.blocked = blocked
        self.deletedById = deletedById
    }
}

class NoteRowAttributes: ObservableObject {
    @Published var firstQuote: NRPost? = nil
    
    init(firstQuote: NRPost? = nil) {
        self.firstQuote = firstQuote
    }
}



class HighlightAttributes: ObservableObject {
    @Published var contact: NRContact? = nil
    
    public var authorPubkey: String?
    public var anyName: String? {
        get {
            if let anyName = contact?.anyName {
                return anyName
            }
            guard let authorPubkey = authorPubkey else { return nil }
            return String(authorPubkey.suffix(11))
        }
    }
    public var url: String?
    // TODO: Add naddr support

    init(contact: NRContact? = nil, authorPubkey: String? = nil, url: String? = nil) {
        self.contact = contact
        self.authorPubkey = authorPubkey
        self.url = url
    }
}

class ReplyingToAttributes: ObservableObject {
    @Published var replyingToUsernamesMarkDown: AttributedString? = nil
    
    init(replyingToUsernamesMarkDown: AttributedString? = nil) {
        self.replyingToUsernamesMarkDown = replyingToUsernamesMarkDown
    }
}
