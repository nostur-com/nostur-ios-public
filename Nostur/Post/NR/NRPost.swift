//
//  NRPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import Foundation
import Combine

public typealias NRPostID = String

// NRPost SHOULD BE CREATED IN BACKGROUND THREAD
class NRPost: ObservableObject, Identifiable, Hashable, Equatable {
    
    @Published var groupedRepliesSorted: [NRPost] = []
    @Published var groupedRepliesNotWoT: [NRPost] = []
    
    // Has some subclass-ObservableObjects to isolate rerendering to specific view attributes:
    // PostOrThreadAttributes, PostRowDeletableAttributes, NoteRowAttributes, PFPAttributes
    
    class PostOrThreadAttributes: ObservableObject {
        @Published var parentPosts:[NRPost] = []
        
        init(parentPosts:[NRPost] = []) {
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
        @Published var firstQuote:NRPost? = nil
        
        init(firstQuote:NRPost? = nil) {
            self.firstQuote = firstQuote
        }
    }
    
    class PFPAttributes: ObservableObject {
        @Published var contact:NRContact? = nil
        
        init(contact:NRContact? = nil) {
            self.contact = contact
        }
    }
    
    class HighlightAttributes: ObservableObject {
        @Published var contact:NRContact? = nil
        
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

        init(contact:NRContact? = nil, authorPubkey:String? = nil, url:String? = nil) {
            self.contact = contact
            self.authorPubkey = authorPubkey
            self.url = url
        }
    }
    
    class ReplyingToAttributes: ObservableObject {
        @Published var replyingToUsernamesMarkDown:AttributedString? = nil
        
        init(replyingToUsernamesMarkDown:AttributedString? = nil) {
            self.replyingToUsernamesMarkDown = replyingToUsernamesMarkDown
        }
    }

    // Seperate ObservableObjects for view performance optimization
    var postOrThreadAttributes: PostOrThreadAttributes
    var postRowDeletableAttributes: PostRowDeletableAttributes
    var noteRowAttributes: NoteRowAttributes
    var pfpAttributes: PFPAttributes
    var highlightAttributes: HighlightAttributes = HighlightAttributes()
    var replyingToAttributes: ReplyingToAttributes
    var footerAttributes: FooterAttributes
    var ownPostAttributes: OwnPostAttributes
    
    let SPAM_LIMIT_P:Int = 50
 
    static func == (lhs: NRPost, rhs: NRPost) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let createdAt:Date
    let created_at:Int64
    let ago:String
    
    let id:NRPostID
    let kind:Int64
    
    let pubkey:String
    
    var subject:String?
    var content:String?
    var plainText:String = ""
    var contentElements:[ContentElement] = [] // NoteRow.Kind1
    var contentElementsDetail:[ContentElement] = [] // PostDetail.Kind1
    var via:String?
    
    var contact:NRContact?  {
        get { pfpAttributes.contact }
        set {
            DispatchQueue.main.async {
                self.pfpAttributes.contact = newValue
            }
        }
    }
    
    var replyingToUsernamesMarkDown:AttributedString?  {
        get { replyingToAttributes.replyingToUsernamesMarkDown }
        set {
            DispatchQueue.main.async {
                self.replyingToAttributes.replyingToUsernamesMarkDown = newValue
            }
        }
    }
    
    var referencedContacts:[NRContact] = []
    
    private var _parentPosts: [NRPost] // access from BG only through .parentPosts
    
    var parentPosts: [NRPost] { // access from BG only
        get { _parentPosts }
        set {
            _parentPosts = newValue // Thread 1 - Data race in Nostur.NRPost.parentPosts.setter : Swift.Array<Nostur.NRPost> at 0x112075600
            DispatchQueue.main.async {
                self.postOrThreadAttributes.parentPosts = newValue
            }
        }
    }
    
    private var _replies: [NRPost] = []

    var replies: [NRPost] {
        get { NRState.shared.nrPostQueue.sync { _replies } }
        set { NRState.shared.nrPostQueue.async(flags: .barrier) { self._replies = newValue } }
    }
    
    private var _repliesToRoot: [NRPost] = [] {
        didSet {
            if withGroupedReplies {
                self.groupRepliesToRoot.send([])
            }
        }
    }

    var repliesToRoot: [NRPost] {
        get { NRState.shared.nrPostQueue.sync { _repliesToRoot } }
        set { NRState.shared.nrPostQueue.async(flags: .barrier) { self._repliesToRoot = newValue } }
    }
    var groupedReplies = [NRPost]()
    
    let isRepost:Bool
    var repostedHeader = ""
    var threadPostsCount:Int
    var isTruncated:Bool = false
    
    var replyToId:String?
    var replyToRootId:String?
    
    var _replyTo:NRPost?
    var _replyToRoot:NRPost?
    
    var firstQuoteId:String?
    
    var replyTo:NRPost?  {
        get { NRState.shared.nrPostQueue.sync { _replyTo } }
        set { NRState.shared.nrPostQueue.async(flags: .barrier) { self._replyTo = newValue } }
    }
    
    var replyToRoot:NRPost? {
        get { NRState.shared.nrPostQueue.sync { _replyToRoot } }
        set { NRState.shared.nrPostQueue.async(flags: .barrier) { self._replyToRoot = newValue } }
    }
    
    var firstQuote:NRPost? {
        get { noteRowAttributes.firstQuote }
        set {
            DispatchQueue.main.async {
                self.noteRowAttributes.firstQuote = newValue
            }
        }
    }
  
    var firstE:String? // Needed for muting
    var deletedById:String? {
        get { postRowDeletableAttributes.deletedById }
        set {
            DispatchQueue.main.async {
                self.postRowDeletableAttributes.deletedById = newValue
            }
        }
    }
    
    let event:Event // Only touch this in BG context!!!
    
    var missingPs:Set<String> // missing or have no contact info
    var fastTags:[(String, String, String?, String?)] = []
    
    var fileMetadata:KindFileMetadata?
    
    var relays:String
    var following = false
    var blocked: Bool {
        get { postRowDeletableAttributes.blocked }
        set {
            DispatchQueue.main.async {
                self.postRowDeletableAttributes.blocked = newValue
            }
        }
    }

    
    var linkPreviewURLs:[URL] = []
    var imageUrls:[URL] = []
    var previewWeights:PreviewWeights?
    var plainTextOnly = false
    var flags:String {
        get { ownPostAttributes.flags }
        set {
            DispatchQueue.main.async {
                self.ownPostAttributes.flags = newValue
            }
        }
    }
    var aTag:String = ""
    var isPreview = false // hide 'Sent to 0 relays' in preview footer, disable animated gifs, Text instead of NRText
    
    var anyName:String {
        if let contact = contact {
            return contact.anyName
        }
        return String(pubkey.suffix(11))
    }
    
    private var withFooter = true // Use false for embedded posts, where footer is not visible so we don't load/listen for likes, replies etc.
    private var withReplyTo = false
    private var withGroupedReplies = false
    private var withReplies = false // Will listen for replies from import save, and process for rendering in bg
    private var withRepliesCount = false // Will listen for replies but only for counter, no processing for rendering
    private var withParents = false
    
    private var groupRepliesToRoot = PassthroughSubject<[NRPost], Never>()
    
    let inWoT:Bool // This is just one of the inputs to determine spam or not, should have more inputs.
    let isSpam:Bool // Should use this in all views to hide or not
    
    // article stuff
    var eventId: String? // d tag
    var eventTitle: String?
    var eventSummary: String?
    var eventPublishedAt: Date?
    var eventImageUrl: URL?
    var eventUrl: URL?
    var mostRecentId: String?
    
    init(event: Event, withFooter:Bool = true, withReplyTo:Bool = false, withParents:Bool = false, withReplies:Bool = false, plainText:Bool = false, withRepliesCount:Bool = false, isPreview:Bool = false, cancellationId:UUID? = nil) {
        var isAwaiting = false
        
        self.event = event // Only touch this in BG context!!!
        self.postRowDeletableAttributes = PostRowDeletableAttributes(blocked: Self.isBlocked(pubkey: event.pubkey), deletedById: event.deletedById)
        self.isPreview = isPreview
        self.id = event.id
        self.pubkey = event.pubkey
        self.kind = event.kind
        self.createdAt = event.date
        self.created_at = event.created_at
        self.ago = event.ago
        let parentPosts = withParents ? event.parentEvents.map { NRPost(event: $0) } : []
        self.postOrThreadAttributes = PostOrThreadAttributes(parentPosts: parentPosts)
        self._parentPosts = parentPosts
        
        let replies = withReplies && withFooter ? event.replies_.map { NRPost(event: $0) } : []
        self._replies = replies
        self.ownPostAttributes = OwnPostAttributes(isOwnPost: NRState.shared.fullAccountPubkeys.contains(pubkey), relaysCount: event.relays.split(separator: " ").count, cancellationId: cancellationId, flags: event.flags)
        
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
        self.isRepost = event.isRepost
        
        self.firstQuoteId = event.firstQuoteId
        if let firstQuote = event.firstQuote, let firstQuoteId = event.firstQuoteId {
            if firstQuote.kind == 0 {
                bg().delete(firstQuote)
                event.firstQuote = nil
                Importer.shared.existingIds.removeValue(forKey: firstQuoteId)
                self.noteRowAttributes = NoteRowAttributes()
                EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.005a"); isAwaiting = true
            }
            else {
                self.noteRowAttributes = NoteRowAttributes(firstQuote: NRPost(event: firstQuote, withReplies: withReplies, withRepliesCount: withRepliesCount))
            }
        } // why event.firstQuote_ doesn't work??
        else if let firstQuoteId = event.firstQuoteId, let firstQuote = try? Event.fetchEvent(id: firstQuoteId, context: bg()) {
            if firstQuote.kind == 0 {
                bg().delete(firstQuote)
                event.firstQuote = nil
                Importer.shared.existingIds.removeValue(forKey: firstQuoteId)
                self.noteRowAttributes = NoteRowAttributes()
                EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.005b"); isAwaiting = true
            }
            else {
                self.noteRowAttributes = NoteRowAttributes(firstQuote: NRPost(event: firstQuote, withFooter: false, withReplies: withReplies, withRepliesCount: withRepliesCount))
            }
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
//        self.mentionsCount = event.mentionsCount
        
        
        self.relays = event.relays
        self.fastTags = event.fastTags
        self.plainText = NRTextParser.shared.copyPasteText(event, text: event.content ?? "").text
        self.withParents = withParents
        self.withReplies = withReplies
        self.withReplyTo = withReplyTo
        self.withRepliesCount = withRepliesCount
        self.plainTextOnly = plainText
        self.inWoT = event.inWoT
        self.isSpam = event.isSpam
        self.aTag = event.aTag
        
        // Show if ["client", "Name", ""31990:..." ...]
        // Hide if ["client", ""31990:..." ..]
        // Also show if  ["proxy", "https:\/\/....", "activitypub"]
        self.via = self.fastTags.first(where: { $0.0 == "client" && $0.1.prefix(6) != "31990:" })?.1
        if self.via == nil {
            if let proxy = self.fastTags.first(where: { $0.0 == "proxy" && $0.2 != nil })?.2 {
                self.via = String(format: "%@ (proxy)", proxy)
            }
        }
        
        let nrContacts = event.contacts_.map { NRContact(contact: $0) }
        self.referencedContacts = nrContacts
        
        if let contact = event.contact_ {
            self.pfpAttributes = PFPAttributes(contact: NRContact(contact: contact, following: self.following))
        }
        else {
            self.pfpAttributes = PFPAttributes()
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.001"); isAwaiting = true
        }
        
        var missingPs = Set<String>()
        if self.pfpAttributes.contact == nil {
            missingPs.insert(event.pubkey)
        }
        else if let c = self.pfpAttributes.contact, c.metadata_created_at == 0 {
            missingPs.insert(event.pubkey)
        }
        let eventContactPs = (nrContacts.compactMap({ contact in
            if contact.metadata_created_at != 0 {
                return contact.pubkey
            }
            return nil
        }) + [event.pubkey])
        
        // Some clients put P in kind 6. Ignore that because the contacts are in the reposted post, not in the kind 6.
        // TODO: Should only fetch if the Ps are going to be on screen. Could be just for notifications.
        if kind != 6 {
            event.fastPs.prefix(SPAM_LIMIT_P).forEach { (tag, pubkey, hint, _) in
                if !eventContactPs.contains(pubkey) {
                    missingPs.insert(pubkey)
                }
            }
        }

        // Start doing kind specific stuff here (TODO)
        switch kind {
        case 1063:
            self.fileMetadata = getKindFileMetadata(event: event)
            
        case 9802:
            let highlightUrl = event.fastTags.first(where: { $0.0 == "r" } )?.1
            let highlightAuthorPubkey:String? = event.fastTags.first(where: { $0.0 == "p" } )?.1
            
            let highlightContact:NRContact? = if let contact = event.contacts?.first(where: { $0.pubkey == highlightAuthorPubkey } ) {
                NRContact(contact: contact, following: isFollowing(contact.pubkey))
            }
            else {
                nil
            }
            
            if let highlightAuthorPubkey = highlightAuthorPubkey, highlightContact == nil || (highlightContact?.metadata_created_at ?? 0) == 0 {
                missingPs.insert(highlightAuthorPubkey)
            }
            self.highlightAttributes = HighlightAttributes(contact: highlightContact, authorPubkey: highlightAuthorPubkey, url: highlightUrl)
            
        case 30023, 34235:
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
        default:
            break
        }
        
        if !plainText { // plainText is actually plainTextOnly, for rendering in muted spam stuff
            let (contentElementsDetail, linkPreviewURLs, imageUrls) = (kind == 30023) ? NRContentElementBuilder.shared.buildArticleElements(event) : NRContentElementBuilder.shared.buildElements(event)
            self.linkPreviewURLs = linkPreviewURLs
            self.imageUrls = imageUrls
            
            self.contentElementsDetail = contentElementsDetail
            let (contentElements, previewWeights) = filteredForPreview(contentElementsDetail)
            self.contentElements = contentElements
            
            for index in self.contentElements.indices {
                switch self.contentElements[index] {
                case .nevent1(let identifier):
                    guard let id = identifier.eventId else { continue }
                    guard let event = try? Event.fetchEvent(id: id, context: bg()) else { continue }
                    self.contentElements[index] = ContentElement.nrPost(NRPost(event: event))
                case .note1(let noteId):
                    guard let id = hex(noteId) else { continue }
                    guard let event = try? Event.fetchEvent(id: id, context: bg()) else { continue }
                    self.contentElements[index] = ContentElement.nrPost(NRPost(event: event))
                case .noteHex(let id):
                    guard let event = try? Event.fetchEvent(id: id, context: bg()) else { continue }
                    self.contentElements[index] = ContentElement.nrPost(NRPost(event: event))
                default:
                    continue
                }
            }
            
            self.previewWeights = previewWeights
        }
        
        self.following = isFollowing(event.pubkey)
        
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
        
        self.subject = fastTags.first(where: { $0.0 == "subject" })?.1
        if let subject {
            self.subject = String(subject.prefix(255)) // 255 SPAM LIMIT
        }
        
        // Moved from .body to here because String interpolation is expensive (https://developer.apple.com/wwdc23/10160)
        self.repostedHeader = String(localized:"\(contact?.anyName ?? "...") reposted", comment: "Heading for reposted post: '(Name) reposted'")
        setupSubscriptions()
    }
    
    private static func isBlocked(pubkey:String) -> Bool {
        return Nostur.blocks().contains(pubkey)
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    private func setupSubscriptions() {
        // Don't listen if there is no need to listen (performance?)
        
        if !missingPs.isEmpty {
            contactSavedListener()
        }
        
        if firstQuoteId != nil {
            quotedPostListener()
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
        
        if withReplyTo {
            replyAndReplyRootListener()
        }
        
        relaysUpdatedListener()
        updateNRPostListener()
        isFollowingListener()
        unpublishListener()
        
        groupRepliesToRoot
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] nrPosts in
                guard let self = self else { return }
                self._groupRepliesToRoot(nrPosts)
            }
            .store(in: &subscriptions)
    }
    
    private func relaysUpdatedListener() {
        event.relaysUpdated
//            .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink { [weak self] relays in
                guard let self = self else { return }
//                self.objectWillChange.send()
                self.relays = relays
                let relaysCount = relays.split(separator: " ").count
                DispatchQueue.main.async {
                    self.ownPostAttributes.objectWillChange.send()
                    self.ownPostAttributes.relaysCount = relaysCount
                }
            }
            .store(in: &subscriptions)
    }
    
    private func updateNRPostListener() {
        event.updateNRPost
//            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                
                self.relays = event.relays
                let relaysCount = event.relays.split(separator: " ").count
                let flags = event.flags
                let cancellationId = event.cancellationId

                DispatchQueue.main.async {
                    self.ownPostAttributes.objectWillChange.send()
                    self.ownPostAttributes.relaysCount = relaysCount
                    self.ownPostAttributes.flags = flags
                    self.ownPostAttributes.cancellationId = cancellationId
                }
            }
            .store(in: &subscriptions)
    }
    
    private func isFollowingListener() {
        receiveNotification(.followersChanged)
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let followingPubkeys = notification.object as! Set<String>
                let isFollowing = followingPubkeys.contains(self.pubkey)
                if isFollowing != self.following {
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.following = isFollowing
                        if (isFollowing) {
                            self.contact?.following = isFollowing
                            self.contact?.couldBeImposter = 0
                        }
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func unpublishListener() {

        // the undo can be in the replies, so don't check for own account keys yet
        receiveNotification(.unpublishedNRPost)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard self.withGroupedReplies else { return }
                let nrPost = notification.object as! NRPost
                guard replies.contains(where: { $0.id == nrPost.id }) || repliesToRoot.contains(where: { $0.id == nrPost.id })
                else { return }
                self.loadGroupedReplies()
            }
            .store(in: &subscriptions)
        
        
        // Only for our accounts, handle undo of this post.
        guard NRState.shared.fullAccountPubkeys.contains(self.pubkey) else { return }
        
        receiveNotification(.publishingEvent)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let eventId = notification.object as! String
                guard eventId == self.id else { return }
                
                DispatchQueue.main.async {
                    self.ownPostAttributes.objectWillChange.send()
                    self.ownPostAttributes.cancellationId = nil
                }
            }
            .store(in: &subscriptions)
    }
    
    // For rerendering ReplyingToFragment, or setting .contact
    // Or Rebuilding content elements for mentions in text
    private func contactSavedListener() {

        // Rerender ReplyingToFragment when the new contact is saved (only if we replyToId is set)
        // Rerender content elements also for mentions in text
        Importer.shared.contactSaved
            .subscribe(on: DispatchQueue.global())
            .filter({ [weak self] pubkey in
                guard let self = self else { return false }
                return self.missingPs.contains(pubkey)
            })
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.global())
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                if self.kind == 6 {
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.repostedHeader = String(localized:"\(self.contact?.anyName ?? "...") reposted", comment: "Heading for reposted post: '(Name) reposted'")
                    }
                }
                else {
                    if self.replyToId != nil {
                        self.rerenderReplyingToFragment()
                    }
                    self.rebuildContentElements()
                    
                    if self.kind == 9802 && self.highlightAttributes.authorPubkey == pubkey {
                        bg().perform {
                            guard let contact = Contact.fetchByPubkey(pubkey, context: bg()) else { return }
                            let nrContact = NRContact(contact: contact, following: isFollowing(pubkey))
                            DispatchQueue.main.async {
                                self.highlightAttributes.objectWillChange.send()
                                self.highlightAttributes.contact = nrContact
                            }
                        }
                    }
                }
            }
            .store(in: &subscriptions)
       
        // Remove from missingPs so we don't fetch again at any .onAppear
        Importer.shared.contactSaved
            .subscribe(on: DispatchQueue.global())
            .filter({ [weak self] pubkey in
                guard let self = self else { return false }
                return self.missingPs.contains(pubkey)
            })
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                self.missingPs.remove(pubkey)
            }
            .store(in: &subscriptions)
        
        Importer.shared.contactSaved
            .subscribe(on: DispatchQueue.global())
            .filter({ [weak self] pubkey in
                guard let self = self else { return false }
                return self.pubkey == pubkey
            })
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.global())
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                bg().perform { [weak self] in
                    guard let contact = self?.event.contact else { return }
                    let nrContact = NRContact(contact: contact, following: self?.following ?? false)
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                        self?.contact = nrContact
                    }
                }
            }
            .store(in: &subscriptions)
    }

    
    private func rebuildContentElements() {
        bg().perform { [weak self] in
            guard let self = self else { return }
            
            let (contentElementsDetail, _, _) = (kind == 30023) ? NRContentElementBuilder.shared.buildArticleElements(event) : NRContentElementBuilder.shared.buildElements(event)
            let (contentElements, _) = filteredForPreview(contentElementsDetail)
            
            DispatchQueue.main.async {
                // self.objectWillChange.send() // Not needed? because this is only for things not on screen yet
                // for on screen we already use .onReceive
                // if it doens't work we need to change let nrPost:NRPost to @ObserverdObject var nrPost:NRPost on ContentRenderer
                // and enable self.objectWillChange.send() here.
                self.contentElementsDetail = contentElementsDetail
                self.contentElements = contentElements
            }
        }
    }
    private func rerenderReplyingToFragment() {
        bg().perform { [weak self] in
            guard let self = self else { return }
            if let replyingToMarkdown = NRReplyingToBuilder.shared.replyingToUsernamesMarkDownString(self.event) {
                let md = try? AttributedString(markdown: replyingToMarkdown)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.replyingToUsernamesMarkDown = md
                }
            }
        }
    }
    
    private func quotedPostListener() {
        self.event.firstQuoteUpdated
            .sink { firstQuote in
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    let nrFirstQuote = NRPost(event: firstQuote, withReplyTo: true, withReplies: withReplies)
                    self.firstQuote = nrFirstQuote
                }
            }
            .store(in: &subscriptions)
    }
    
    private func postDeletedListener() {
        self.event.postDeleted
            .receive(on: RunLoop.main)
            .sink { [weak self] deletedById in
                guard let self = self else { return }
                self.deletedById = deletedById
            }
            .store(in: &subscriptions)
    }
    
    private func replyAndReplyRootListener() {
        self.event.replyToUpdated
            .sink { replyTo in
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    let nrReplyTo = NRPost(event: replyTo, withReplyTo: true)
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.replyTo = nrReplyTo
                        // self.loadReplyTo() // need this??
                    }
                }
            }
            .store(in: &subscriptions)
        
        self.event.replyToRootUpdated
            .sink { replyToRoot in
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    let nrReplyToRoot = NRPost(event: replyToRoot, withReplyTo: true)
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.replyToRoot = nrReplyToRoot
                        // self.loadReplyTo() // need this??
                    }
                }
            }
            .store(in: &subscriptions)
        
        
    }
    
    private func repliesListener() {
        self.event.repliesUpdated
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { replies in
                let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    let nrReplies = replies
                            .filter { !blocks().contains($0.pubkey) }
                            .map { event in
                                let nrPost = NRPost(event: event, cancellationId: cancellationIds[event.id])
                                return nrPost
                            }
                    
                    let replyPFPs = nrReplies
                        .compactMap { reply in
                            return followingPFP(reply.pubkey)
                        }
                        .uniqued(on: ({ $0 }))
                        .prefix(8)
                    
                    if (withGroupedReplies) {
                        self.groupRepliesToRoot.send(nrReplies)
                    }
                    else {
                        self.event.repliesCount = Int64(nrReplies.count) // Fix wrong count in db
                        DispatchQueue.main.async {
                            self.objectWillChange.send()
                            self.replies = nrReplies
                            
                            self.footerAttributes.objectWillChange.send()
                            self.footerAttributes.repliesCount = Int64(nrReplies.count)
                            self.footerAttributes.replyPFPs = Array(replyPFPs)
                        }
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    // Same as repliesListener but only for counts
    private func repliesCountListener() {
        guard !withReplies else { return } // Skip if we already have repliesListener, which makes repliesCountListener not needed
        self.event.repliesUpdated
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { replies in
                self.footerAttributes.objectWillChange.send()
                self.footerAttributes.repliesCount = Int64(replies.count)
            }
            .store(in: &subscriptions)
    }
    
    private func loadReplies() {
        if (!self.withReplies) {
            self.withReplies = true
            repliesListener()
        }
        let ctx = bg()
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        ctx.perform { [weak self] in
            guard let self = self else { return }
            
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 1 AND replyToId == %@ AND NOT pubkey IN %@", String(self.id), blocks()) // _PFManagedObject_coerceValueForKeyWithDescription + 1472 (NSManagedObject.m:0) - Maybe fix with String(self.id)
            if let foundReplies = try? ctx.fetch(fr) {
                if let existingReplies = self.event.replies {
                    self.event.replies = existingReplies.union(Set(foundReplies))
                }
                else {
                    self.event.replies = Set(foundReplies)
                }
            }
            let nrReplies = self.event.replies_
                .filter { !blocks().contains($0.pubkey) }
                .map { NRPost(event: $0, cancellationId: cancellationIds[$0.id]) }
            self.event.repliesCount = Int64(nrReplies.count) // Fix wrong count in db
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.replies = nrReplies
                self.footerAttributes.objectWillChange.send()
                self.footerAttributes.repliesCount = Int64(nrReplies.count)
            }
        }
    }
    
    public func loadReplyTo() {
        if (!self.withReplyTo) {
            self.withReplyTo = true
            replyAndReplyRootListener()
        }
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard self.replyTo == nil else { return }
            guard let replyToId = self.replyToId else { return }
            
            if let replyTo = try? Event.fetchEvent(id: replyToId, context: bg()) {
                let nrReplyTo = NRPost(event: replyTo, withReplyTo: true)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.replyTo = nrReplyTo
                }
            }
        }
    }
    
    @MainActor public func loadParents() {
        let beforeThreadPostsCount = self.threadPostsCount
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard !self.withParents else { return }
            self.withParents = true
            
            let parents = Event.getParentEvents(self.event, fixRelations: true)//, until:self.id)
            let parentPosts = parents.map { NRPost(event: $0) }
            let threadPostsCount = 1 + self.event.parentEvents.count
            
            guard beforeThreadPostsCount != threadPostsCount else { return }
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.parentPosts = parentPosts
                self.threadPostsCount = threadPostsCount
            }
        }
    }
    
    var mainEvent:Event {
        DataProvider.shared().viewContext.object(with: event.objectID) as! Event
    }
    
    @MainActor public func like(_ reactionContent:String = "+") -> NEvent {
        self.footerAttributes.objectWillChange.send()
        if (reactionContent == "+") {
            self.footerAttributes.liked = true
        }
        else {
            self.footerAttributes.reactions.insert(reactionContent)
        }
        bg().perform {
            self.event.likesCount += 1
        }
        
        return EventMessageBuilder.makeReactionEvent(reactingTo: mainEvent, reactionContent: reactionContent)
    }
    
    @MainActor public func unlike(_ reactionContent:String = "+") {
        self.footerAttributes.objectWillChange.send()
        if (reactionContent == "+") {
            self.footerAttributes.liked = false
        }
        else {
            self.footerAttributes.reactions.remove(reactionContent)
        }
        bg().perform {
            self.event.likesCount -= 1
        }
    }
    
    @MainActor public func unpublish() {
        guard let cancellationId = ownPostAttributes.cancellationId else { return }
        _ = Unpublisher.shared.cancel(cancellationId)
        self.ownPostAttributes.objectWillChange.send()
        self.ownPostAttributes.cancellationId = nil
        bg().perform {
            bg().delete(self.event)
            bgSave()
            DispatchQueue.main.async {
                sendNotification(.unpublishedNRPost, self)
            }
        }
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
        self.noteRowAttributes.firstQuote?.blocked = false
        self.firstQuote!.blocked = false
    }
    
    private var renderedReplyIds: Set<NRPostID> = []
}

extension NRPost { // Helpers for grouped replies
    
    // To make repliesSorted work we need repliesToRoot first (.loadRepliesToRoot())
    func sortGroupedReplies(_ nrPosts: [NRPost]) -> [NRPost] { // Read from bottom to top.
        if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
            return nrPosts
                // 4. Everything else last, newest at bottom
                .sorted(by: { $0.created_at < $1.created_at })
                // 3. People you follow third
                .sorted(by: { $0.following && !$1.following })
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
        
        // With WoT enabeled with add filter nr 5.
        return nrPosts
            // 5. People outside WoT last
            .filter { $0.inWoT || NRState.shared.accountPubkeys.contains($0.pubkey) }
        
            // 4. Everything else in WoT last, newest at bottom
            .sorted(by: { $0.created_at < $1.created_at })
            // 3. People you follow third
            .sorted(by: { $0.following && !$1.following })
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
            .filter { !$0.inWoT && !NRState.shared.accountPubkeys.contains($0.pubkey)}
            .sorted(by: { $0.created_at < $1.created_at })
    }
    
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
            if let replyToRootId = self.replyToRootId { // We are not root, so load replies for actual root instead
                fr.predicate = NSPredicate(format: "replyToRootId = %@ AND kind == 1 AND NOT pubkey IN %@", replyToRootId, blocks())
            }
            else {
                fr.predicate = NSPredicate(format: "replyToRootId = %@ AND kind == 1 AND NOT pubkey IN %@", self.id, blocks())
            }
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true )]
            let repliesToRoot = (try? bg().fetch(fr)) ?? []
            for reply in repliesToRoot { // Add to queue because some may be missing .replyTo
                EventRelationsQueue.shared.addAwaitingEvent(reply, debugInfo: "reply in .repliesToRoot")
            }
            let nrRepliesToRoot = repliesToRoot
                .filter { !NRState.shared.blockedPubkeys.contains($0.pubkey) }
                .map { event in
                    let nrPost = NRPost(event: event, withReplyTo: false, withParents: false, withReplies: false, plainText: false, cancellationId: cancellationIds[event.id])
                    return nrPost
                } // Don't load replyTo/parents here, we do it in groupRepliesToRoot()
            self.repliesToRoot = nrRepliesToRoot
        }
    }
    
    private func repliesToRootListener() {
        self.event.replyToRootUpdated
//            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { reply in
                let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
                
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    
                    let nrReply = NRPost(event: reply, withReplyTo: false, withParents: false, withReplies: false, plainText: false, cancellationId: cancellationIds[reply.id]) // Don't load replyTo/parents here, we do it in groupRepliesToRoot()
                    self.repliesToRoot.append(nrReply)
                    self.groupRepliesToRoot.send(self.replies)
                }
            }
            .store(in: &subscriptions)
    }
    
    var repliesToLeaf:[NRPost] {
        // if we are not root we cannot use replyToRootId
        // we need only the replies under our leaf id
        // so we have to traverse manually:
        
        // we just start from a leaf and traverse up, if we hit our self.id its ours,
        // else it will go up to the actual root and we dont need it
        
        var ourReplies:[NRPost] = []
        for post in repliesToRoot {
            if traversesUpToThisPost(post.event) {
                ourReplies.append(post)
            }
        }
        return ourReplies
    }
    
    private func traversesUpToThisPost(_ event:Event) -> Bool {
        var currentEvent:Event? = event
        while currentEvent != nil {
            if let replyToId = currentEvent?.replyToId, replyToId == self.id {
                return true
            }
            currentEvent = currentEvent?.replyTo__
        }
        return false
    }
    
    private func _groupRepliesToRoot(_ newReplies:[NRPost]) {
        bg().perform { [weak self] in
            guard let self = self else { return }
            renderedReplyIds.removeAll()
            let replies = (newReplies.isEmpty ? self.replies : newReplies)
            // Load parents/replyTo
            let groupedThreads = (replies + (self.replyToRootId != nil ? self.repliesToLeaf : self.repliesToRoot))
                .uniqued(on: { $0.id })
                .filter({ nrPost in
                    return !NRState.shared.blockedPubkeys.contains(nrPost.pubkey)
                })
                .filter { // Only take eventual replies by author, or direct replies to root by others
                    $0.pubkey == self.pubkey ||
                    $0.replyToId == self.id
                }
                .map { reply in
                    // use until:self.id so we don't render duplicates
                    reply.event.parentEvents = Event.getParentEvents(reply.event, fixRelations: true, until:self.id)
                    reply.parentPosts = reply.event.parentEvents.map { NRPost(event: $0) }
                    reply.threadPostsCount = 1 + reply.event.parentEvents.count

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
                
                let firstId = thread.event.parentEvents.first?.id ?? thread.id
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
                return partialResult.union(Set(nrPost.event.parentEvents.map { $0.id }))
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
            
            self.event.repliesCount = Int64(replies.count) // Fix wrong count in db
            DispatchQueue.main.async {
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
