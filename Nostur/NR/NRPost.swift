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
    
    private var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue")
    
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
    let note1:String
    let kind:Int64
    
    let pubkey:String
    let npub:String
    
    var content:String?
    var plainText:String = ""
    var replyingToUsernamesMarkDown:AttributedString?
    var contentElements:[ContentElement] = [] // NoteRow.Kind1
    var contentElementsDetail:[ContentElement] = [] // PostDetail.Kind1
    var renderedText:AttributedString = ""
    
    var _contact:NRContact?
    var contact:NRContact?  {
        get { nrPostQueue.sync { _contact } }
        set { nrPostQueue.async { self._contact = newValue } }
    }
    
    var referencedContacts:[NRContact] = []
    
    private var _parentPosts:[NRPost] = []
    var parentPosts: [NRPost] {
        get { nrPostQueue.sync { _parentPosts } }
        set { nrPostQueue.async { self._parentPosts = newValue } }
    }
    
    private var _replies: [NRPost] = []

    var replies: [NRPost] {
        get { nrPostQueue.sync { _replies } }
        set { nrPostQueue.async { self._replies = newValue } }
    }
    
    
    let isRepost:Bool
    var threadPostsCount:Int
    var isTruncated:Bool = false
    
    var replyToId:String?
    var replyToRootId:String?
    
    var _replyTo:NRPost?
    var _replyToRoot:NRPost?
    
    var firstQuoteId:String?
    var _firstQuote:NRPost?
    
    var replyTo:NRPost?  {
        get { nrPostQueue.sync { _replyTo } }
        set { nrPostQueue.async { self._replyTo = newValue } }
    }
    
    var replyToRoot:NRPost? {
        get { nrPostQueue.sync { _replyToRoot } }
        set { nrPostQueue.async { self._replyToRoot = newValue } }
    }
    
    var firstQuote:NRPost? {
        get { nrPostQueue.sync { _firstQuote } }
        set { nrPostQueue.async { self._firstQuote = newValue } }
    }
    
    
    
    var firstE:String? // Needed for muting
    
    var deletedById:String?
    
    let event:Event // Only touch this in BG context!!!
    
    var missingPs:[String] // missing or have no contact info
    var fastTags:[(String, String, String?)] = []
    
    
    var isHighlight:Bool { highlightData != nil}
    var highlightData:KindHightlight?
    var fileMetadata:KindFileMetadata?
    
    var relays:String = ""
    
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
    
    var anyDisplayName:String {
        if let contact = contact {
            return contact.anyDisplayName
        }
        return String(npub.prefix(11))
    }
    var anyUsername:String {
        if let contact = contact {
            return contact.anyUsername
        }
        return String(npub.prefix(11))
    }
    
    private var withReplyTo = false
    private var withReplies = false
    private var withParents = false
    
    init(event: Event, withReplyTo:Bool = false, withParents:Bool = false, withReplies:Bool = false, plainText:Bool = false) {
        self.event = event // Only touch this in BG context!!!
        self.id = event.id
        self.note1 = "..." //event.noteId
        self.pubkey = event.pubkey
        self.npub = "....."  // event.npub
        self.kind = event.kind
        self.createdAt = event.date
        self.created_at = event.created_at
        self.ago = event.ago
        self._parentPosts = withParents ? event.parentEvents.map { NRPost(event: $0) } : []
        self._replies = withReplies ? event.replies_.map { NRPost(event: $0) } : []
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
        self.plainText = plainText ? NRTextParser.shared.copyPasteText(event, text: event.noteTextPrepared).text : ""
        self.withParents = withParents
        self.withReplies = withReplies
        self.withReplyTo = withReplyTo
        
        var isAwaiting = false
        if let contact = event.contact {
            self._contact = NRContact(contact: contact)
        }
        else {
            EventRelationsQueue.shared.addAwaitingEvent(event); isAwaiting = true
        }
        
        let nrContacts = event.contacts_.map { NRContact(contact: $0) }
        self.referencedContacts = nrContacts
        
        var missingPs = [String]()
        if self._contact == nil {
            missingPs.append(event.pubkey)
        }
        else if let c = self._contact, c.metadata_created_at == 0 {
            missingPs.append(event.pubkey)
        }
        let eventContactPs = nrContacts.compactMap({ contact in
            if contact.metadata_created_at != 0 {
                return contact.pubkey
            }
            return nil
        })
        event.fastPs.forEach { (tag, pubkey, hint) in
            if !eventContactPs.contains(pubkey) {
                missingPs.append(pubkey)
            }
        }
        self.missingPs = missingPs
        if !isAwaiting && self.missingPs.count > 0 {
            EventRelationsQueue.shared.addAwaitingEvent(event); isAwaiting = true
        }
        
        self.replyToId = event.replyToId
        if withReplyTo, let replyTo = event.replyTo {
            self.replyTo = NRPost(event: replyTo)
        }
        else if !isAwaiting && event.replyToId != nil {
            EventRelationsQueue.shared.addAwaitingEvent(event); isAwaiting = true
        }
        
        self.replyToRootId = event.replyToRootId
        if withReplyTo, let replyToRoot = event.replyToRoot {
            self.replyToRoot = NRPost(event: replyToRoot)
        }
        else if !isAwaiting && event.replyToRootId != nil {
            EventRelationsQueue.shared.addAwaitingEvent(event); isAwaiting = true
        }
        
        self.firstQuoteId = event.firstQuoteId
        if let firstQuote = event.firstQuote {
            self.firstQuote = NRPost(event: firstQuote)
        }
        else if !isAwaiting && event.firstQuoteId != nil {
            EventRelationsQueue.shared.addAwaitingEvent(event); isAwaiting = true
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
    
        let (contentElementsDetail, linkPreviewURLs) = NRContentElementBuilder.shared.buildElements(event)
        self.linkPreviewURLs = linkPreviewURLs
        let firstQuote = contentElements.first(where: { element in
                if case .note1 = element {
                    return true
                }
                if case .nevent1 = element {
                    return true
                }
                return false
        })
        
        self.contentElementsDetail = contentElementsDetail
        self.contentElements = contentElementsDetail
        // Todo fix, short preview view for NoteRow (not PostDetail)
        
//        self.contentElements =  {
//            var gotVideo = false
//            return contentElementsDetail
//                .filter { element in
//                    if case .video = element {
//                        if (!gotVideo) {
//                            gotVideo = true
//                            return true
//                        }
//                        return false
//                    }
//                    if case .note1 = element {
//                        return element == firstQuote
//                    }
//                    if case .nevent1 = element {
//                        return element == firstQuote
//                    }
//                    else {
//                        return true
//                    }
//                }
//        }()
        self.renderedText = NRTextParser.shared.parseText(event, text: event.noteTextPrepared).text
        
        self.bookmarked = isBookmarked()
        self.liked = isLiked()
        self.replied = isReplied()
        self.reposted = isReposted()
        self.hasPrivateNote = _hasPrivateNote()
        
        listenForChanges()
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
    
    private func isLiked() -> Bool {
        if let account = NosturState.shared.bgAccount {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND reactionToId == %@ AND pubkey == %@ AND kind == 7", created_at, id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            //TODO: should check for "+","👍","🤙","❤️","🫂","🤗","😘","😍","💯","🤩","⚡️","🔥","💥","🚀"
            let count = (try? DataProvider.shared().bg.count(for: fr)) ?? 0
            return count > 0
        }
        return false
    }
    
    private func isReplied() -> Bool {
        if let account = NosturState.shared.bgAccount {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at > %i AND replyToId == %@ AND pubkey == %@ AND kind == 1", created_at, id, account.publicKey)
            fr.fetchLimit = 1
            fr.resultType = .countResultType
            //TODO: should check for "+","👍","🤙","❤️","🫂","🤗","😘","😍","💯","🤩","⚡️","🔥","💥","🚀"
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
        return KindHightlight(
            highlightAuthorPubkey: event.fastTags.first(where: { $0.0 == "p" } )?.1,
            highlightAuthorPicture: event.contacts?.first?.picture,
            highlightAuthorIsFollowing: false, // TODO: FIX highlight isfollowing
            highlightAuthorName: event.contacts?.first?.authorName,
            highlightUrl: event.fastTags.first(where: { $0.0 == "r" } )?.1
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
    
    private func listenForChanges() {
        // Don't listen if there is no need to listen (performance?)
        
        if missingPs.count > 0 {
            replyingToListener()
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
        
        if withReplyTo {
            replyAndReplyRootListener()
        }
        
        actionListener()
    }
    
    private func actionListener() {
        receiveNotification(.postAction)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let action = notification.object as! PostActionNotification
                guard action.eventId == self.id else { return }
                
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
                
                self.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
    
    // For rerendering ReplyingToFragment, or setting .contact
    private func replyingToListener() {

        receiveNotification(.contactSaved)
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ pTag in
                self.missingPs.contains(pTag)
            })
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                self.rerenderReplyingToFragment()
            }
            .store(in: &subscriptions)
        
        receiveNotification(.contactSaved)
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ pTag in
                self.missingPs.contains(pTag)
            })
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                self.missingPs.removeAll(where: { $0 == pubkey } )
            }
            .store(in: &subscriptions)
        
        receiveNotification(.contactSaved)
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ pTag in
                self.pubkey == pTag
            })
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                DataProvider.shared().bg.perform { [weak self] in
                    guard let contact = self?.event.contact else { return }
                    self?.contact = NRContact(contact: contact)
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func rerenderReplyingToFragment() {
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            if let replyingToMarkdown = NRReplyingToBuilder.shared.replyingToUsernamesMarkDownString(self.event) {
                self.replyingToUsernamesMarkDown = try? AttributedString(markdown: replyingToMarkdown)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    private func quotedPostListener() {
        receiveNotification(.postSaved).sink { [weak self] notification in
            guard let self = self else { return }
            let eventId = notification.object as! String
            guard self.firstQuoteId == eventId else { return }
            
            DataProvider.shared().bg.perform { [weak self] in
                guard let self = self else { return }
                
                if let firstQuote = self.event.firstQuote {
                    self.firstQuote = NRPost(event: firstQuote)
                    
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                }
            }
        }
        .store(in: &subscriptions)
    }
    
    private func postDeletedListener() {
        receiveNotification(.postDeleted).sink { [weak self] notification in
            guard let self = self else { return }
            let eventId = notification.object as! String
            guard self.id == eventId else { return }
            
            DataProvider.shared().bg.perform { [weak self] in
                self?.deletedById = self?.event.deletedById
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
        }
        .store(in: &subscriptions)
    }
    
    private func replyAndReplyRootListener() {
        receiveNotification(.postSaved).sink { [weak self] notification in
            guard let self = self else { return }
            let eventId = notification.object as! String
            guard self.replyToId == eventId || self.replyToRootId == eventId else { return }
            
            DataProvider.shared().bg.perform { [weak self] in
                if let eventReplyTo = self?.event.replyTo {
                    self?.replyTo = NRPost(event: eventReplyTo)
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                }
                else {
                    self?.loadReplyTo()
                }
            }
        }
        .store(in: &subscriptions)
    }
    
    private func repliesListener() {
        receiveNotification(.replySaved).sink { [weak self] notification in
            guard let self = self else { return }
            let replyToId = notification.object as! String
            guard self.id == replyToId else { return }
            
            DataProvider.shared().bg.perform { [weak self] in
                guard let self = self else { return }
                self.replies = self.event.replies_.map { NRPost(event: $0) }
                
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
        .store(in: &subscriptions)
    }
    
    public func loadReplies() {
        self.withReplies = true
        repliesListener()
        
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            self.replies = self.event.replies_.map { NRPost(event: $0) }
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    public func loadReplyTo() {
        self.withReplyTo = true
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            guard self.replyTo == nil else { return }
            guard let replyToId = self.replyToId else { return }
            
            if let replyTo = try? Event.fetchEvent(id: replyToId, context: DataProvider.shared().bg) {
                self.replyTo = NRPost(event: replyTo)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    var mainEvent:Event {
        DataProvider.shared().viewContext.object(with: event.objectID) as! Event
    }
}

struct KindFileMetadata {
    var url:String
    var m:String?
    var hash:String?
    var dim:String?
    var blurhash:String?
}

struct KindHightlight {
    var highlightAuthorPubkey:String?
    var highlightAuthorPicture:String?
    var highlightAuthorIsFollowing:Bool
    var highlightAuthorName:String?
    var highlightUrl:String?
}

/// add back later
///

//var following:Bool
//var plainText:String
//var renderedText:AttributedString
//var replyingToUsernamesMarkDown:AttributedString? // See ReplyingToFragment
//var imageUrls:[URL] // See ImageViewer
//var renderedElements:[MarkdownElement] // NoteRow.Kind1
//var renderedElementsDetail:[MarkdownElement] // PostDetail.Kind1
//
//var liked = false
//var reposted = false
//var replied = false

struct PostActionNotification {
    let type:ActionType
    let eventId:String
    
    var bookmarked:Bool = false
    var hasPrivateNote:Bool = false
    
    enum ActionType {
        case bookmark
        case liked
        case reposted
        case replied
        case privateNote
    }
}
