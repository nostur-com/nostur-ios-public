//
//  Post.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import Foundation
import CoreData

//Equatable
struct VPost: Identifiable, Equatable, Hashable {
    
    static func == (lhs: VPost, rhs: VPost) -> Bool {
        lhs.post.objectID == rhs.post.objectID
        && lhs.liked == rhs.liked
        && lhs.repliesCount == rhs.repliesCount
        && lhs.mentionsCount == rhs.mentionsCount
        && lhs.likesCount == rhs.likesCount
        && lhs.zapTally == rhs.zapTally
        && lhs.reposted == rhs.reposted
        && lhs.isBookmarked == rhs.isBookmarked
        && lhs.vContact?.hashValue == rhs.vContact?.hashValue
        && lhs.replyingToUsernamesMarkDown == rhs.replyingToUsernamesMarkDown
//        && lhs.hasPrivateNote == rhs.hasPrivateNote
//        && lhs.firstQuote == rhs.firstQuote
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(post.objectID)
        hasher.combine(liked)
        hasher.combine(repliesCount)
        hasher.combine(mentionsCount)
        hasher.combine(likesCount)
        hasher.combine(zapTally)
        hasher.combine(reposted)
        hasher.combine(isBookmarked)
        hasher.combine(vContact?.hashValue)
        hasher.combine(replyingToUsernamesMarkDown)
//        hasher.combine(hasPrivateNote)
//        hasher.combine(firstQuote)
    }
    
    let post:Event
    
    let pubkey:String
    let npub:String
    let id:String
    let note1:String
    let plainText:String
    let renderedText:AttributedString
    let isRepost:Bool
    let mentionedPosts:[VPost] // instead of firstQuote...
    let created_at:Int64
    let createdAt:Date
    // hmm .ago?
    
    let replyingToUsernamesMarkDown:String? // See ReplyingToFragment
    
    let imageUrls:[URL] // See ImageViewer
    
    // Footer things
    let liked:Bool
    let repliesCount:Int64
    let mentionsCount:Int64
    let likesCount:Int64
    let zapTally:Int64
    let reposted:Bool
    
    let isBookmarked:Bool
    let vContact:VContact?
    
    var name:String {
        "testttt" // TODO replace with .authorName... emoji check etc
    }
    
    var firstQuote:VPost? {
        mentionedPosts.first
    }
    
    let hasPrivateNote:Bool
    
    var username:String { // Username is in contact, but maybe we dont have contact so fallback here
        vContact?.username ?? String((npub.prefix(11)))
    }
    
    var displayName:String { // Username is in contact, but maybe we dont have contact so fallback here
        vContact?.displayName ?? String((npub.prefix(11)))
    }
    
}



struct VContact: Identifiable, Equatable, Hashable {
    
    static func == (lhs: VContact, rhs: VContact) -> Bool {
        lhs.contact.objectID == rhs.contact.objectID
        && lhs.hasPrivateNote == rhs.hasPrivateNote
        && lhs.updated_at == rhs.updated_at
        && lhs.nip05verifiedAt == rhs.nip05verifiedAt
        && lhs.isFollowing == rhs.isFollowing
        && lhs.anyLud == rhs.anyLud
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(contact.objectID)
        hasher.combine(hasPrivateNote)
        hasher.combine(updated_at)
        hasher.combine(nip05verifiedAt)
        hasher.combine(isFollowing)
        hasher.combine(anyLud)
        
    }
    
    let contact:Contact
    
    var id:String { pubkey }
    let pubkey:String
    let npub:String // bech32
    let pictureUrl:String?
    let displayName:String // Check NoteHeader for how to fill
    let username:String // Check NoteHeader for how to fill
    
    let nip05:String?
    let nip05verifiedAt:Date?
    let isNip05Verified:Bool
    
    let isFollowing:Bool // how does this update? Need to set here or no? (needed in NoteMenu)
    let updated_at:Int64
    
    let anyLud:Bool
    let hasPrivateNote:Bool
}



class VTransformer {
    private let pubkey:String
    private let context: NSManagedObjectContext
    private let replyingToBuilder:ReplyingToUsernamesBuilder
    private let postTextRenderer:RenderedPostTextBuilder
    private let account:Account?
    
    init(pubkey:String, context: NSManagedObjectContext? = nil) {
        self.pubkey = pubkey
        self.context = context ?? DataProvider.shared().viewContext
        self.replyingToBuilder = ReplyingToUsernamesBuilder(context: self.context)
        self.postTextRenderer = RenderedPostTextBuilder(context: self.context)
        self.account = try? Account.fetchAccount(publicKey: pubkey, context: self.context)
    }
    
    func contactToVContact(_ contact:Contact) -> VContact {
        let vContact = VContact(contact: contact,
                                pubkey: contact.pubkey,
                                npub: contact.npub,
                                pictureUrl: contact.picture,
                                displayName: contact.authorName,
                                username: contact.username,
                                nip05: contact.nip05,
                                nip05verifiedAt: contact.nip05verifiedAt,
                                isNip05Verified: contact.nip05veried,
                                isFollowing: isFollowing(contact:contact), // TODO: FIXME isFollowing
                                updated_at: contact.updated_at,
                                anyLud: contact.anyLud,
                                hasPrivateNote: hasPrivateNote(contact:contact)
        
        )
        return vContact
    }
    
    func eventToVPost(_ event:Event) -> VPost {
        let vContact = event.contact != nil ? contactToVContact(event.contact!) : nil
        
        let vPost = VPost(post:event,
                          pubkey: event.pubkey,
                          npub: event.npub,
                          id: event.id,
                          note1: event.noteId,
                          plainText: postTextRenderer.copyPasteText(event),
                          renderedText: postTextRenderer.renderedText(event),
                          isRepost: event.isRepost,
                          mentionedPosts: event.firstQuote != nil ? [eventToVPost(event.firstQuote!)] : [],
                          created_at: event.created_at,
                          createdAt: Date(timeIntervalSince1970: Double(event.created_at)),
                          replyingToUsernamesMarkDown: replyingToBuilder.replyingToUsernamesMarkDownString(event),
                          imageUrls: event.content != nil ? getImgUrlsFromContent(event.content!) : [],
                          liked: event.liked,
                          repliesCount: event.repliesCount,
                          mentionsCount: event.mentionsCount,
                          likesCount: event.likesCount,
                          zapTally: event.zapTally,
                          reposted: event.reposted,
                          isBookmarked: isBookmarked(post: event),
                          vContact: vContact,
                          hasPrivateNote: hasPrivateNote(post:event)
        )
        
        return vPost
    }
    
    func hasPrivateNote(post:Event? = nil, contact:Contact? = nil) -> Bool {
        (account?
            .privateNotes?
            .filter { ($0.post != nil && $0.post == post) || ($0.contact != nil && $0.contact == contact) }
            .count ?? 0) != 0
    }
    
    func isBookmarked(post:Event) -> Bool {
        account?.bookmarks?.contains(post) ?? false
    }
    
    func isFollowing(contact:Contact) -> Bool {
        account?.follows?.contains(contact) ?? false
    }
    
    
}
