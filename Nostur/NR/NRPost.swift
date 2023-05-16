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
//    let note1:String
    let kind:Int64
    
    let pubkey:String
//    let npub:String
    
    var subject:String?
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
    var previewWeights:PreviewWeights
    
    var anyDisplayName:String {
        if let contact = contact {
            return contact.anyDisplayName
        }
        return String(pubkey.suffix(11))
    }
    var anyUsername:String {
        if let contact = contact {
            return contact.anyUsername
        }
        return String(pubkey.suffix(11))
    }
    
    private var withReplyTo = false
    private var withReplies = false
    private var withParents = false
    
    init(event: Event, withReplyTo:Bool = false, withParents:Bool = false, withReplies:Bool = false, plainText:Bool = false) {
        self.event = event // Only touch this in BG context!!!
        self.id = event.id
        self.pubkey = event.pubkey
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
        self.plainText = NRTextParser.shared.copyPasteText(event, text: event.content ?? "").text
        self.withParents = withParents
        self.withReplies = withReplies
        self.withReplyTo = withReplyTo
        
        let (contentElementsDetail, linkPreviewURLs) = NRContentElementBuilder.shared.buildElements(event)
        self.linkPreviewURLs = linkPreviewURLs
        
        self.contentElementsDetail = contentElementsDetail
        let (contentElements, previewWeights) = filteredForPreview(contentElementsDetail)
        self.contentElements = contentElements
        self.previewWeights = previewWeights
        
        var isAwaiting = false
        if let contact = event.contact {
            self._contact = NRContact(contact: contact)
        }
        else {
            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NRPost.001"); isAwaiting = true
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
        }) + [event.pubkey]
        event.fastPs.forEach { (tag, pubkey, hint) in
            if !eventContactPs.contains(pubkey) {
                missingPs.append(pubkey)
            }
        }
        self.missingPs = missingPs
        if !isAwaiting && self.missingPs.count > 0 {
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
            self.firstQuote = NRPost(event: firstQuote)
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
        
        self.renderedText = NRTextParser.shared.parseText(event, text: event.noteTextPrepared).output
        
        self.bookmarked = isBookmarked()
        self.liked = isLiked()
        self.replied = isReplied()
        self.reposted = isReposted()
        self.hasPrivateNote = _hasPrivateNote()
        
        self.subject = fastTags.first(where: { $0.0 == "subject" })?.1
        
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
        var hlNrContact:NRContact?
        if let contact = event.contacts?.first {
            hlNrContact = NRContact(contact: contact)
        }
        return KindHightlight(
            highlightAuthorPubkey: event.fastTags.first(where: { $0.0 == "p" } )?.1,
            highlightAuthorPicture: event.contacts?.first?.picture,
            highlightAuthorIsFollowing: false, // TODO: FIX highlight isfollowing
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
    
    private func listenForChanges() {
        // Don't listen if there is no need to listen (performance?)
        
        if missingPs.count > 0 {
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
        
        if withReplyTo {
            replyAndReplyRootListener()
        }
        
        actionListener()
        likesListener()
        zapsListener()
    }
    
    private func likesListener() {
        event.likesDidChange
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] likes in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.likesCount = likes
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
    }
    
    private func actionListener() {
        receiveNotification(.postAction)
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
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ pTag in
                self.missingPs.contains(pTag)
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
            .map({ notification in
                return notification.object as! Ptag
            })
            .filter({ pTag in
                self.missingPs.contains(pTag)
            })
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] pubkey in
                guard let self = self else { return }
                self.objectWillChange.send() // Need to update the views or they still have the old .missingPs
                self.missingPs.removeAll(where: { $0 == pubkey } )
            }
            .store(in: &subscriptions)
        
        // Create self.contact = nrContact
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
                    let nrContact = NRContact(contact: contact)
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                        self?.contact = nrContact
                        self?.missingPs.removeAll(where: { $0 == pubkey } )
                    }
                }
            }
            .store(in: &subscriptions)
    }

    
    private func rebuildContentElements() {
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            
            let (contentElementsDetail, _) = NRContentElementBuilder.shared.buildElements(event)
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
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.replies = nrReplies
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    public func loadReplies() {
        if (!self.withReplies) {
            self.withReplies = true
            repliesListener()
        }
        
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            let nrReplies = self.event.replies_.map { NRPost(event: $0) }
            DispatchQueue.main.async {
                self.objectWillChange.send()
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
    var highlightNrContact: NRContact?
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


class PreviewWeights {
    var posts = 0.0
    var videos = 0.0
    var pictures = 0.0
    var linkPreviews = 0.0
    var other = 0.0
    var text = 0.0
    
    var weight:Double {
        var weight  = (posts * 0.8)
            weight += (videos * 0.8)
            weight += (pictures * 0.8)
            weight += (linkPreviews * 0.3)
            weight += (other * 0.8)
            weight += (text * 0.0000001)
        
        return weight
    }
    
    var moreItems:Bool {
        (morePosts + moreVideos + morePictures + moreLinkPreviews + moreOther) > 0
    }
    
    var moreItemsCount:Int {
        (morePosts + moreVideos + morePictures + moreLinkPreviews + moreOther)
    }
    
    var morePosts = 0
    var moreVideos = 0
    var morePictures = 0
    var moreLinkPreviews = 0
    var moreOther = 0
    var moreText = 0
}

func filteredForPreview(_ contentElements:[ContentElement]) -> ([ContentElement], PreviewWeights) {
    let w = PreviewWeights()
    
    let previewElements = contentElements.filter { element in
        switch element {
        case .note1:
            w.posts += 1;
            guard w.weight < 1 else {
                w.morePosts += 1
                return false
            }
            return true
        case .noteHex:
            w.posts += 1;
            guard w.weight < 1 else {
                w.morePosts += 1
                return false
            }
            return true
        case .lnbc:
            w.other += 1;
            guard w.weight < 1 else {
                w.moreOther += 1
                return false
            }
            return true
        case .image:
            w.pictures += 1;
            guard w.weight < 1 else {
                w.morePictures += 1
                return false
            }
            return true
        case .video:
            w.videos += 1;
            guard w.weight < 1 else {
                w.moreVideos += 1
                return false
            }
            return true
        case .linkPreview:
            w.linkPreviews += 1;
            guard w.weight < 1 else {
                w.moreLinkPreviews += 1
                return false
            }
            return true
        case .postPreviewImage:
            return true
        case .nevent1:
            w.posts += 1;
            guard w.weight < 1 else {
                w.morePosts += 1
                return false
            }
            return true
        case .nprofile1:
            w.other += 1;
            guard w.weight < 1 else {
                w.moreOther += 1
                return false
            }
            return true
        case .text:
            w.text += 1;
            guard w.weight < 1 else {
                w.moreText += 1
                return false
            }
            return true
        default:
            w.other += 1;
            guard w.weight < 1 else {
                w.moreOther += 1
                return false
            }
            return true
        }
    }
    
    return (previewElements, w)
}
