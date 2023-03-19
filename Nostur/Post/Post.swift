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
        lhs.id == rhs.id
        && lhs.replyingToUsernamesMarkDown == rhs.replyingToUsernamesMarkDown
        && lhs.plainText == rhs.plainText
        && lhs.renderedText == rhs.renderedText
        && lhs.event.liked == rhs.event.liked
        && lhs.event.likesCount == rhs.event.likesCount
        && lhs.event.reposted == rhs.event.reposted
        && lhs.event.firstQuote == rhs.event.firstQuote
        && lhs.event.zapsCount == rhs.event.zapsCount
        && lhs.event.mentionsCount == rhs.event.mentionsCount
        && lhs.event.bookmarkedBy == rhs.event.bookmarkedBy
        && lhs.event.repliesCount == rhs.event.repliesCount
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(replyingToUsernamesMarkDown)
        hasher.combine(plainText)
        hasher.combine(renderedText)
        hasher.combine(event.liked)
        hasher.combine(event.likesCount)
        hasher.combine(event.reposted)
        hasher.combine(event.firstQuote)
        hasher.combine(event.zapsCount)
        hasher.combine(event.mentionsCount)
        hasher.combine(event.bookmarkedBy)
        hasher.combine(event.contacts)
        hasher.combine(event.repliesCount)
    }
    
    let id:String
    let event:Event
    let created_at:Int64
    let npub:String
    let note1:String
    var plainText:String
    var renderedText:AttributedString
    var replyingToUsernamesMarkDown:String? // See ReplyingToFragment
    var imageUrls:[URL] // See ImageViewer
    var displayName:String
        
    var name:String {
        "testttt" // TODO replace with .authorName... emoji check etc
    }
    
    // todo maybe to firstQuote here....
}



struct VPostData {
    let created_at:Int64
    let npub:String
    let note1:String
    var plainText:String
    var renderedText:AttributedString
    var replyingToUsernamesMarkDown:String? // See ReplyingToFragment
    var imageUrls:[URL] // See ImageViewer
    var displayName:String
}

class VPostTransformer {
    static let shared = VPostTransformer()
    
    let context:NSManagedObjectContext
    let replyingToBuilder:ReplyingToUsernamesBuilder
    let postTextRenderer:RenderedPostTextBuilder
    
    init(_ context:NSManagedObjectContext? = nil) {
        self.context = context ?? DataProvider.shared().viewContext
        self.replyingToBuilder = ReplyingToUsernamesBuilder(self.context)
        self.postTextRenderer = RenderedPostTextBuilder(self.context)
    }
    
    func toVPost(_ event:Event) -> VPost {
        return VPost(
            id: event.id,
            event: event,
            created_at: event.created_at,
            npub: event.npub,
            note1: event.noteId,
            plainText: postTextRenderer.copyPasteText(event),
            renderedText: postTextRenderer.renderedText(event),
            replyingToUsernamesMarkDown: replyingToBuilder.replyingToUsernamesMarkDownString(event),
            imageUrls: event.content != nil ? getImgUrlsFromContent(event.content!) : [],
            displayName: event.contact?.authorName ?? String((event.npub.prefix(11)))
        )
    }
    
    func vPostData(_ event:Event) -> VPostData {
        return VPostData(
            created_at: event.created_at,
            npub: event.npub,
            note1: event.noteId,
            plainText: postTextRenderer.copyPasteText(event),
            renderedText: postTextRenderer.renderedText(event),
            replyingToUsernamesMarkDown: replyingToBuilder.replyingToUsernamesMarkDownString(event),
            imageUrls: event.content != nil ? getImgUrlsFromContent(event.content!) : [],
            displayName: event.contact?.authorName ?? String((event.npub.prefix(11)))
        )
    }

}
