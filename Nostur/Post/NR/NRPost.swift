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
    var replyingToUsernamesMarkDown:AttributedString?
    var contentElements:[ContentElement] = [] // NoteRow.Kind1
    var contentElementsDetail:[ContentElement] = [] // PostDetail.Kind1
    
    var _contact:NRContact?
    var contact:NRContact?  {
        get { NosturState.shared.nrPostQueue.sync { _contact } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._contact = newValue } }
    }
    
    var referencedContacts:[NRContact] = []
    
    private var _parentPosts:[NRPost] = []
    var parentPosts: [NRPost] {
        get { NosturState.shared.nrPostQueue.sync { _parentPosts } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._parentPosts = newValue } }
    }
    
    private var _replies: [NRPost] = []

    var replies: [NRPost] {
        get { NosturState.shared.nrPostQueue.sync { _replies } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._replies = newValue } }
    }
    
    
    private var _repliesToRoot: [NRPost] = [] {
        didSet {
            if withGroupedReplies {
                self.groupRepliesToRoot.send([])
            }
        }
    }

    var repliesToRoot: [NRPost] {
        get { NosturState.shared.nrPostQueue.sync { _repliesToRoot } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._repliesToRoot = newValue } }
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
    var _firstQuote:NRPost?
    
    var replyTo:NRPost?  {
        get { NosturState.shared.nrPostQueue.sync { _replyTo } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._replyTo = newValue } }
    }
    
    var replyToRoot:NRPost? {
        get { NosturState.shared.nrPostQueue.sync { _replyToRoot } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._replyToRoot = newValue } }
    }
    
    var firstQuote:NRPost? {
        get { NosturState.shared.nrPostQueue.sync { _firstQuote } }
        set { NosturState.shared.nrPostQueue.async(flags: .barrier) { self._firstQuote = newValue } }
    }
  
    var firstE:String? // Needed for muting
    var deletedById:String?
    
    let event:Event // Only touch this in BG context!!!
    
    var missingPs:Set<String> // missing or have no contact info
    var fastTags:[(String, String, String?, String?)] = []
    
    var isHighlight:Bool { highlightData != nil}
    var highlightData:KindHightlight?
    var fileMetadata:KindFileMetadata?
    
    var relays:String = ""
    
    var zapState:Event.ZapState?
    var following = false
    @Published var blocked = false
    @Published var cancellationId:UUID? = nil // if set, will show 'undo send' view
    var replied = false
    var liked = false
    var reposted = false
    var bookmarked = false
    var hasPrivateNote = false
    var repliesCount:Int64 = 0
    var mentionsCount:Int64 = 0
    var likesCount:Int64 = 0
    var zapsCount:Int64 = 0
    var zapTally:Int64 = 0
    var imageUrls:[URL] = [] // SmoothList uses this for prefetching
    var linkPreviewURLs:[URL] = []
    var previewWeights:PreviewWeights?
    var plainTextOnly = false
    var flags:String = ""
    var aTag:String = ""
    
    var anyName:String {
        if let contact = contact {
            return contact.anyName
        }
        return String(pubkey.suffix(11))
    }
    
    private var withReplyTo = false
    private var withGroupedReplies = false
    private var withReplies = false // Will listen for replies from import save, and process for rendering in bg
    private var withRepliesCount = false // Will listen for replies but only for counter, no processing for rendering
    private var withParents = false
    
    private var groupRepliesToRoot = PassthroughSubject<[NRPost], Never>()
    
    let inWoT:Bool // This is just one of the inputs to determine spam or not, should have more inputs.
    let isSpam:Bool // Should use this in all views to hide or not
    
    // article stuff
    var articleId:String?
    var articleTitle:String?
    var articleSummary:String?
    var articlePublishedAt:Date?
    var articleImageURL:URL?
    var mostRecentId:String?
    
    init(event: Event, withReplyTo:Bool = false, withParents:Bool = false, withReplies:Bool = false, plainText:Bool = false, withRepliesCount:Bool = false) {
        self.event = event // Only touch this in BG context!!!
        self.id = event.id
        self.pubkey = event.pubkey
        self.kind = event.kind
        self.createdAt = event.date
        self.created_at = event.created_at
        self.ago = event.ago
        self._parentPosts = withParents ? event.parentEvents.map { NRPost(event: $0) } : []
        self._replies = withReplies ? event.replies_.map { NRPost(event: $0) } : []
        self._repliesToRoot = []
        self.threadPostsCount = 1 + event.parentEvents.count
        self.isRepost = event.isRepost
        self.deletedById = event.deletedById
        self.repliesCount = event.repliesCount
        self.mentionsCount = event.mentionsCount
        self.zapsCount = event.zapsCount
        self.likesCount = event.likesCount
        self.zapTally = event.zapTally
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
        self.flags = event.flags
        self.aTag = event.aTag
        
        // article?
        if kind == 30023 {
            articleId = event.articleId
            articleTitle = event.articleTitle
            articleSummary = event.articleSummary
            articlePublishedAt = event.articlePublishedAt
            if let articleImage = event.articleImage, let url = URL(string: articleImage) {
                articleImageURL = url
            }
            mostRecentId = event.mostRecentId
        }
        
        if !plainText { // plainText is actually plainTextOnly, for rendering in muted spam stuff
            let (contentElementsDetail, linkPreviewURLs) = (kind == 30023) ? NRContentElementBuilder.shared.buildArticleElements(event) : NRContentElementBuilder.shared.buildElements(event)
            self.linkPreviewURLs = linkPreviewURLs
            
            self.contentElementsDetail = contentElementsDetail
            let (contentElements, previewWeights) = filteredForPreview(contentElementsDetail)
            self.contentElements = contentElements
            self.previewWeights = previewWeights
        }
        
        self.following = NosturState.shared.bgFollowingPublicKeys.contains(event.pubkey)
        
        var isAwaiting = false
        if let contact = event.contact_ {
            self._contact = NRContact(contact: contact, following: self.following)
        }
        else {
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.001"); isAwaiting = true
        }
        
        let nrContacts = event.contacts_.map { NRContact(contact: $0) }
        self.referencedContacts = nrContacts
        
        var missingPs = Set<String>()
        if self._contact == nil {
            missingPs.insert(event.pubkey)
        }
        else if let c = self._contact, c.metadata_created_at == 0 {
            missingPs.insert(event.pubkey)
        }
        let eventContactPs = nrContacts.compactMap({ contact in
            if contact.metadata_created_at != 0 {
                return contact.pubkey
            }
            return nil
        }) + [event.pubkey]
        
        // Some clients put P in kind 6. Ignore that because the contacts are in the reposted post, not in the kind 6.
        // TODO: Should only fetch if the Ps are going to be on screen. Could be just for notifications.
        if kind != 6 {
            event.fastPs.prefix(SPAM_LIMIT_P).forEach { (tag, pubkey, hint, _) in
                if !eventContactPs.contains(pubkey) {
                    missingPs.insert(pubkey)
                }
            }
        }
        
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
        
        self.firstQuoteId = event.firstQuoteId
        if let firstQuote = event.firstQuote {
            self.firstQuote = NRPost(event: firstQuote, withRepliesCount: withRepliesCount)
        } // why event.firstQuote_ doesn't work??
        else if let firstQuoteId = event.firstQuoteId,  let firstQuote = try? Event.fetchEvent(id: firstQuoteId, context: DataProvider.shared().bg) {
            self.firstQuote = NRPost(event: firstQuote, withRepliesCount: withRepliesCount)
        }
        else if !isAwaiting && event.firstQuoteId != nil {
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.005"); isAwaiting = true
        }
        
        if event.kind == 9802 {
            self.highlightData = getHighlightData(event: event)
        }
        
        if event.kind == 1063 {
            self.fileMetadata = getKindFileMetadata(event: event)
        }
        
        if let content = event.content {
            self.content = content
            self.imageUrls = getImgUrlsFromContent(content)
        }
        
        if let replyingToMarkdown = NRReplyingToBuilder.shared.replyingToUsernamesMarkDownString(event) {
            self.replyingToUsernamesMarkDown = try? AttributedString(markdown: replyingToMarkdown)
        }
        
        if isZapped() {
            self.zapState = .zapReceiptConfirmed
        } else {
            self.zapState = event.zapState
        }
        self.bookmarked = isBookmarked()
        self.liked = isLiked()
        self.replied = isReplied()
        self.reposted = isReposted()
        self.hasPrivateNote = _hasPrivateNote()
        self.blocked = isBlocked()
        
        self.subject = fastTags.first(where: { $0.0 == "subject" })?.1
        if let subject {
            self.subject = String(subject.prefix(255)) // 255 SPAM LIMIT
        }
        
        // Moved from .body to here because String interpolation is expensive (https://developer.apple.com/wwdc23/10160)
        self.repostedHeader = String(localized:"\(contact?.anyName ?? "...") reposted", comment: "Heading for reposted post: '(Name) reposted'")
        setupSubscriptions()
    }
    
    private func isBookmarked() -> Bool {
        if let account = NosturState.shared.bgAccount, let bookmarks = account.bookmarks {
            return bookmarks.contains(event)
        }
        return false
    }
    
    private func _hasPrivateNote() -> Bool {
        if let account = NosturState.shared.bgAccount, let notes = account.privateNotes {
            return notes.first(where: { $0.post == self.event }) != nil
        }
        return false
    }
    
    private func isZapped() -> Bool {
        if let account = NosturState.shared.bgAccount {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind == 9734 AND pubkey == %@ AND tagsSerialized CONTAINS %@", created_at, account.publicKey, serializedE(self.id))
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    private func isLiked() -> Bool {
        if let account = NosturState.shared.bgAccount {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND reactionToId == %@ AND pubkey == %@ AND kind == 7", created_at, id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    private func isBlocked() -> Bool {
        if let account = NosturState.shared.bgAccount {
            return account.blockedPubkeys_.contains(self.pubkey)
        }
        return false
    }
    
    private func isReplied() -> Bool {
        if let account = NosturState.shared.bgAccount {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at > %i AND replyToId == %@ AND pubkey == %@ AND kind == 1", created_at, id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    private func isReposted() -> Bool {
        if let account = NosturState.shared.bgAccount {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at > %i AND repostForId == %@ AND pubkey == %@",
                                       created_at, id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    private func getHighlightData(event: Event) -> KindHightlight {
        var hlNrContact:NRContact?
        if let contact = event.contacts?.first {
            hlNrContact = NRContact(contact: contact)
        }
        return KindHightlight(
            highlightAuthorPubkey: event.fastTags.first(where: { $0.0 == "p" } )?.1,
            highlightAuthorPicture: event.contacts?.first?.picture,
            highlightAuthorIsFollowing: hlNrContact?.following ?? false,
            highlightAuthorName: event.contacts?.first?.authorName,
            highlightUrl: event.fastTags.first(where: { $0.0 == "r" } )?.1,
            highlightNrContact: hlNrContact
        )
    }
    
    private func getKindFileMetadata(event: Event) -> KindFileMetadata {
        return KindFileMetadata(
            url: event.fastTags.first(where: { $0.0 == "url" })?.1 ?? "",
            m: event.fastTags.first(where: { $0.0 == "m" })?.1,
            hash: event.fastTags.first(where: { $0.0 == "hash" })?.1,
            dim: event.fastTags.first(where: { $0.0 == "dim" })?.1,
            blurhash: event.fastTags.first(where: { $0.0 == "blurhash" })?.1
        )
    }
    
    var subscriptions = Set<AnyCancellable>()
    
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
        actionListener()
        likesListener()
        zapsListener()
        isFollowingListener()
        
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
            .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink { [weak self] relays in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.relays = relays
                
                // TODO: Need implement better way to update NRPost fields
                // so we can just do dbEvent.flags = "" instead of hooking into relaysUpdatedListener()
                // or any other listener
                if (self.flags == "nsecbunker_unsigned") {
                    self.flags = ""
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
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    
    private func likesListener() {
        event.likesDidChange
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] likes in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.likesCount = likes
                
                // Also update own like (or slow? disbaled)
//                if !self.liked && isLiked() { // nope. main bg thread mismatch
//                    self.liked = true
//                }
            }
            .store(in: &subscriptions)
    }
    
    private func zapsListener() {
        event.zapsDidChange
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] (count, tally) in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.zapTally = tally
                self.zapsCount = count
            }
            .store(in: &subscriptions)
        
        event.zapStateChanged
            .sink { [weak self] zapState in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.zapState = zapState
                }
            }
            .store(in: &subscriptions)
    }
    
    private func actionListener() {
        receiveNotification(.postAction)
            .subscribe(on: DispatchQueue.global())
            .sink { [weak self] notification in
                guard let self = self else { return }
                let action = notification.object as! PostActionNotification
                guard action.eventId == self.id else { return }
                
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    switch action.type {
                    case .bookmark:
                        self.bookmarked = action.bookmarked
                    case .liked:
                        self.liked = true
                    case .replied:
                        self.replied = true
                    case .reposted:
                        self.reposted = true
                    case .privateNote:
                        self.hasPrivateNote = action.hasPrivateNote
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    // For rerendering ReplyingToFragment, or setting .contact
    // Or Rebuilding content elements for mentions in text
    private func contactSavedListener() {

        // Rerender ReplyingToFragment when the new contact is saved (only if we replyToId is set)
        // Rerender content elements also for mentions in text
        receiveNotification(.contactSaved)
            .subscribe(on: DispatchQueue.global())
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ [weak self] pTag in
                guard let self = self else { return false }
                return self.missingPs.contains(pTag)
            })
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                if self.replyToId != nil {
                    self.rerenderReplyingToFragment()
                }
                self.rebuildContentElements()
            }
            .store(in: &subscriptions)
       
        // Remove from missingPs so we don't fetch again at any .onAppear
        receiveNotification(.contactSaved)
            .subscribe(on: DispatchQueue.global())
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ [weak self] pTag in
                guard let self = self else { return false }
                return self.missingPs.contains(pTag)
            })
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                self.objectWillChange.send() // Need to update the views or they still have the old .missingPs
                self.missingPs.remove(pubkey)
            }
            .store(in: &subscriptions)
        
        // Create self.contact = nrContact
        receiveNotification(.contactSaved)
            .subscribe(on: DispatchQueue.global())
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ [weak self] pTag in
                guard let self = self else { return false }
                return self.pubkey == pTag
            })
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                DataProvider.shared().bg.perform { [weak self] in
                    guard let contact = self?.event.contact else { return }
                    let nrContact = NRContact(contact: contact)
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                        self?.contact = nrContact
                    }
                }
            }
            .store(in: &subscriptions)
    }

    
    private func rebuildContentElements() {
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            
            let (contentElementsDetail, _) = (kind == 30023) ? NRContentElementBuilder.shared.buildArticleElements(event) : NRContentElementBuilder.shared.buildElements(event)
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
        DataProvider.shared().bg.perform { [weak self] in
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
                DataProvider.shared().bg.perform { [weak self] in
                    guard let self = self else { return }
                    let nrFirstQuote = NRPost(event: firstQuote, withReplyTo: true)
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.firstQuote = nrFirstQuote
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func postDeletedListener() {
        self.event.postDeleted
            .receive(on: RunLoop.main)
            .sink { [weak self] deletedById in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.deletedById = deletedById
            }
            .store(in: &subscriptions)
    }
    
    private func replyAndReplyRootListener() {
        self.event.replyToUpdated
            .sink { replyTo in
                DataProvider.shared().bg.perform { [weak self] in
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
                DataProvider.shared().bg.perform { [weak self] in
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
                DataProvider.shared().bg.perform { [weak self] in
                    guard let self = self else { return }
                    let nrReplies = replies.map { NRPost(event: $0) }
                    
                    if (withGroupedReplies) {
                        self.groupRepliesToRoot.send(nrReplies)
                    }
                    else {
                        self.event.repliesCount = Int64(nrReplies.count) // Fix wrong count in db
                        DispatchQueue.main.async {
                            self.objectWillChange.send()
                            self.repliesCount = Int64(nrReplies.count)
                            self.replies = nrReplies
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
                self.objectWillChange.send()
                self.repliesCount = Int64(replies.count)
            }
            .store(in: &subscriptions)
    }
    
    private func loadReplies() {
        if (!self.withReplies) {
            self.withReplies = true
            repliesListener()
        }
        let ctx = DataProvider.shared().bg
        ctx.perform { [weak self] in
            guard let self = self else { return }
            
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 1 AND replyToId == %@", String(self.id)) // _PFManagedObject_coerceValueForKeyWithDescription + 1472 (NSManagedObject.m:0) - Maybe fix with String(self.id)
            if let foundReplies = try? ctx.fetch(fr) {
                if let existingReplies = self.event.replies {
                    self.event.replies = existingReplies.union(Set(foundReplies))
                }
                else {
                    self.event.replies = Set(foundReplies)
                }
            }
            
            let nrReplies = self.event.replies_.map { NRPost(event: $0) }
            self.event.repliesCount = Int64(nrReplies.count) // Fix wrong count in db
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.repliesCount = Int64(nrReplies.count)
                self.replies = nrReplies
            }
        }
    }
    
    public func loadReplyTo() {
        if (!self.withReplyTo) {
            self.withReplyTo = true
            replyAndReplyRootListener()
        }
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            guard self.replyTo == nil else { return }
            guard let replyToId = self.replyToId else { return }
            
            if let replyTo = try? Event.fetchEvent(id: replyToId, context: DataProvider.shared().bg) {
                let nrReplyTo = NRPost(event: replyTo, withReplyTo: true)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.replyTo = nrReplyTo
                }
            }
        }
    }
    
    public func loadParents() {
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            
            let parents = Event.getParentEvents(self.event, fixRelations: true)//, until:self.id)
            let parentPosts = parents.map { NRPost(event: $0) }
            let threadPostsCount = 1 + self.event.parentEvents.count
            
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
    
    @MainActor public func like() {
        self.objectWillChange.send()
        self.liked = true
    }
    
    @MainActor public func unlike() {
        self.objectWillChange.send()
        self.liked = false
        DataProvider.shared().bg.perform {
            self.event.likesCount -= 1
        }
    }
    
    @MainActor public func unpublish() {
        guard let cancellationId = cancellationId else { return }
        let cancelled = Unpublisher.shared.cancel(cancellationId)
        self.objectWillChange.send()
        self.cancellationId = nil
        
        if !cancelled {
            L.og.info("🔴🔴 Unpublish failed")
        }
        else {
            sendNotification(.unpublishedNRPost, self)
        }
    }
    
    @MainActor public func sendNow() {
        guard let cancellationId = cancellationId else { return }
        let didSend = Unpublisher.shared.sendNow(cancellationId)
        self.objectWillChange.send()
        self.cancellationId = nil
        
        if !didSend {
            L.og.info("🔴🔴 Send now failed")
        }
    }
}

extension NRPost { // Helpers for grouped replies
    
    // To make repliesSorted work we need repliesToRoot first (.loadRepliesToRoot())
    var groupedRepliesSorted:[NRPost] { // Read from bottom to top.
        if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
            return groupedReplies
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
        return groupedReplies
            // 5. People outside WoT last
            .filter { $0.inWoT }
        
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
    
    var groupedRepliesNotWoT:[NRPost] { // Read from bottom to top.
        return groupedReplies
            .filter { !$0.inWoT }
            .sorted(by: { $0.created_at < $1.created_at })
    }
    
    public func loadGroupedReplies() {
        self.loadReplies()
        if (!self.withGroupedReplies) {
            self.withGroupedReplies = true
            repliesToRootListener()
        }
        let ctx = DataProvider.shared().bg
        ctx.perform { [weak self] in
            guard let self = self else { return }
            guard let account = NosturState.shared.account?.toBG() else { return }
            let fr = Event.fetchRequest()
            if let replyToRootId = self.replyToRootId { // We are not root, so load replies for actual root instead
                fr.predicate = NSPredicate(format: "replyToRootId = %@ AND kind == 1", replyToRootId)
            }
            else {
                fr.predicate = NSPredicate(format: "replyToRootId = %@ AND kind == 1", self.id)
            }
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true )]
            let repliesToRoot = (try? DataProvider.shared().bg.fetch(fr)) ?? []
            for reply in repliesToRoot { // Add to queue because some may be missing .replyTo
                EventRelationsQueue.shared.addAwaitingEvent(reply, debugInfo: "reply in .repliesToRoot")
            }
            let nrRepliesToRoot = repliesToRoot
                .filter { !Set(account.blockedPubkeys_).contains($0.pubkey) }
                .map { NRPost(event: $0, withReplyTo: false, withParents: false, withReplies: false, plainText: false) } // Don't load replyTo/parents here, we do it in groupRepliesToRoot()
            self.repliesToRoot = nrRepliesToRoot
        }
    }
    
    private func repliesToRootListener() {
        self.event.replyToRootUpdated
//            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { reply in
                DataProvider.shared().bg.perform { [weak self] in
                    guard let self = self else { return }
                    
                    let nrReply = NRPost(event: reply, withReplyTo: false, withParents: false, withReplies: false, plainText: false) // Don't load replyTo/parents here, we do it in groupRepliesToRoot()
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
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            guard let account = NosturState.shared.account?.toBG() else {
                L.og.error("_groupRepliesToRoot: We should have an account here");
                return
            }
            
            let replies = (newReplies.isEmpty ? self.replies : newReplies)
            // Load parents/replyTo
            let groupedThreads = (replies + (self.replyToRootId != nil ? self.repliesToLeaf : self.repliesToRoot))
                .uniqued(on: { $0.id })
                .filter({ nrPost in
                    return !(Set(account.blockedPubkeys_)).contains(nrPost.pubkey)
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
                    uniqueThreads[thread.id] = thread
                    continue // replying to root, so handle like normal reply.
                }
                
                let firstId = thread.parentPosts.first?.id ?? thread.id
                if let existingThread = uniqueThreads[firstId] {
                    if thread.threadPostsCount > existingThread.threadPostsCount {
                        uniqueThreads[firstId] = thread
                    }
                } else {
                    uniqueThreads[firstId] = thread
                }
            }

            // Retrieve the unique items with highest values
            let groupedReplies = Array(uniqueThreads.values)
            
            self.event.repliesCount = Int64(replies.count) // Fix wrong count in db
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.repliesCount = Int64(replies.count)
                self.replies = replies
                self.groupedReplies = groupedReplies
            }
        }
    }
}



