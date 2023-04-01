//
//  Post.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import Foundation
import CoreData

//Equatable
//struct VPost: Identifiable {
struct VPost: Identifiable, Equatable, Hashable {
    static func == (lhs: VPost, rhs: VPost) -> Bool {
        lhs.id == rhs.id
//        && lhs.replyingToUsernamesMarkDown == rhs.replyingToUsernamesMarkDown
//        && lhs.plainText == rhs.plainText
//        && lhs.renderedText == rhs.renderedText
//        && lhs.event.liked == rhs.event.liked
//        && lhs.event.likesCount == rhs.event.likesCount
//        && lhs.event.reposted == rhs.event.reposted
//        && lhs.event.firstQuote == rhs.event.firstQuote
//        && lhs.event.zapsCount == rhs.event.zapsCount
//        && lhs.event.mentionsCount == rhs.event.mentionsCount
//        && lhs.event.bookmarkedBy == rhs.event.bookmarkedBy
//        && lhs.event.repliesCount == rhs.event.repliesCount
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
//        hasher.combine(replyingToUsernamesMarkDown)
//        hasher.combine(plainText)
//        hasher.combine(renderedText)
//        hasher.combine(event.liked)
//        hasher.combine(event.likesCount)
//        hasher.combine(event.reposted)
//        hasher.combine(event.firstQuote)
//        hasher.combine(event.zapsCount)
//        hasher.combine(event.mentionsCount)
//        hasher.combine(event.bookmarkedBy)
//        hasher.combine(event.contacts)
//        hasher.combine(event.repliesCount)
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
    var renderedElements:[MarkdownElement]
    var parentPosts:[VPost]
    
    // This one event + parents are shown as a single Thread, coming from a single vPost
    // So to get the counter correct we can no longer just do vPosts.count
    // We need vPosts.reduce ... .parentPosts.count
    var threadPostsCount:Int
        
    var name:String {
        "testttt" // TODO replace with .authorName... emoji check etc
    }
    
    // todo maybe to firstQuote here....
}



//struct VPostData {
//    let created_at:Int64
//    let npub:String
//    let note1:String
//    var plainText:String
//    var renderedText:AttributedString
//    var replyingToUsernamesMarkDown:String? // See ReplyingToFragment
//    var imageUrls:[URL] // See ImageViewer
//    var displayName:String
//    var renderedElements:[MarkdownElement]
//    var parentPosts:[VPost]
//    var threadPostsCount:Int
//}

class VPostTransformer {
    static let shared = VPostTransformer()
    
    let context:NSManagedObjectContext
    let replyingToBuilder:ReplyingToUsernamesBuilder
    let contentLinkRenderer:ContentLinkRenderer
    
    init(_ context:NSManagedObjectContext? = nil) {
        self.context = context ?? DataProvider.shared().viewContext
        self.replyingToBuilder = ReplyingToUsernamesBuilder(self.context)
        self.contentLinkRenderer = ContentLinkRenderer(self.context)
    }
    
    func toVPost(_ mainEvent:Event, skipParents:Bool? = false) -> VPost? {
        if mainEvent.managedObjectContext == self.context {
            return VPost(
                id: mainEvent.id,
                event: mainEvent, // Should always be main context event
                created_at: mainEvent.created_at,
                npub: mainEvent.npub,
                note1: mainEvent.noteId,
                plainText: contentLinkRenderer.copyPasteText(mainEvent, text: mainEvent.noteText),
                renderedText: contentLinkRenderer.renderedText(mainEvent, text: mainEvent.noteText),
                replyingToUsernamesMarkDown: replyingToBuilder.replyingToUsernamesMarkDownString(mainEvent),
                imageUrls: mainEvent.content != nil ? getImgUrlsFromContent(mainEvent.content!) : [],
                displayName: mainEvent.contact?.authorName ?? String((mainEvent.npub.prefix(11))),
                renderedElements: renderElements(mainEvent),
                parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
                threadPostsCount: 1 + mainEvent.parentEvents.count
            )
        }
        
        guard let privateEvent = try? context.existingObject(with: mainEvent.objectID) as? Event else { return nil }

        return VPost(
            id: privateEvent.id,
            event: mainEvent, // Should always be main context event
            created_at: privateEvent.created_at,
            npub: privateEvent.npub,
            note1: privateEvent.noteId,
            plainText: contentLinkRenderer.copyPasteText(privateEvent, text: privateEvent.noteText),
            renderedText: contentLinkRenderer.renderedText(privateEvent, text: privateEvent.noteText),
            replyingToUsernamesMarkDown: replyingToBuilder.replyingToUsernamesMarkDownString(privateEvent),
            imageUrls: privateEvent.content != nil ? getImgUrlsFromContent(privateEvent.content!) : [],
            displayName: privateEvent.contact?.authorName ?? String((privateEvent.npub.prefix(11))),
            renderedElements: renderElements(privateEvent),
            parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
            threadPostsCount: 1 + mainEvent.parentEvents.count
        )
    }
    
//    func vPostData(_ privateEvent:Event, skipParents:Bool? = false) -> VPostData {
//        return VPostData(
//            created_at: privateEvent.created_at,
//            npub: privateEvent.npub,
//            note1: privateEvent.noteId,
//            plainText: contentLinkRenderer.copyPasteText(privateEvent, text: privateEvent.noteText),
//            renderedText: contentLinkRenderer.renderedText(privateEvent, text: privateEvent.noteText),
//            replyingToUsernamesMarkDown: replyingToBuilder.replyingToUsernamesMarkDownString(privateEvent),
//            imageUrls: privateEvent.content != nil ? getImgUrlsFromContent(privateEvent.content!) : [],
//            displayName: privateEvent.contact?.authorName ?? String((privateEvent.npub.prefix(11))),
//            renderedElements: renderElements(privateEvent),
//            parentPosts: !skipParents! ? privateEvent.parentEvents.map { toVPost($0, skipParents: true) } : []
//        )
//    }
    
//    func getParentPosts(_ event:Event) -> [VPost] {
//        var parentPosts = [VPost]()
//        var currentEvent:Event? = event
//        while (currentEvent != nil) {
//            if let replyTo = currentEvent?.replyTo {
//                parentPosts.append(toVPost(replyTo, skipParents: true))
//                currentEvent = replyTo
//            }
//            currentEvent = nil
//        }
//        return parentPosts
//    }

    func renderElements(_ event:Event) -> [MarkdownElement] {
        let input = event.noteTextPrepared
        //        let input = "The quick brown fox jumps over the lazy lazy dog."
        let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp|bmp)(\?\S+){0,1}\b"###
        let videoUrlPattern = ###"(?i)http(s?):\/\/\S+\.(mp4|mov)"###
        let hashtagPattern = ###"\#\S+"###
        let lightningInvoicePattern = ###"lnbc\S+"###
        let notePattern = ###"nostr:note1[023456789acdefghjklmnpqrstuvwxyz]{58}"###
        let neventPattern = ###"nostr:nevent1\S+"###
        let pattern = "(?i)\(imageUrlPattern)|\(lightningInvoicePattern)|\(notePattern)|\(neventPattern)|\(videoUrlPattern)"
        //        let pattern = ###"\\n"###
        
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [MarkdownElement] = []
        var lastMatchEnd = 0
        
        regex.enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:nonMatch)))
                
                if matchString.matchingStrings(regex: imageUrlPattern).count > 0 {
                    result.append(MarkdownElement.image(URL(string: matchString)!))
                }
                else if matchString.matchingStrings(regex: videoUrlPattern).count > 0 {
                    result.append(MarkdownElement.video(URL(string: matchString)!))
                }
                else if matchString.matchingStrings(regex: notePattern).count > 0 {
                    let m = matchString.matchingStrings(regex:#"note1[023456789acdefghjklmnpqrstuvwxyz]{58}"#)
                    result.append(MarkdownElement.note1(m[0][0]))
                }
                else if matchString.matchingStrings(regex: neventPattern).count > 0 {
                    let m = matchString.matchingStrings(regex:#"nevent1\S+"#)
                    do {
                        let identifier = try ShareableIdentifier(m[0][0])
                        if let noteId = identifier.eventId {
                            result.append(MarkdownElement.noteId(noteId))
                        }
                    }
                    catch {
                        print("problem decoding nevent")
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: lightningInvoicePattern).count > 0 {
                    result.append(MarkdownElement.lnbc(matchString))
                }
                else {
                    result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                }
                
                lastMatchEnd = matchRange.location + matchRange.length
            }
        }
        
        let nonMatchRange = NSRange(location: lastMatchEnd, length: input.utf16.count - lastMatchEnd)
        let nonMatch = (input as NSString).substring(with: nonMatchRange)
        
        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:nonMatch)))
        
        return result
    }
}
