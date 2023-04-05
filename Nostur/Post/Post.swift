//
//  Post.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import Foundation
import CoreData

struct VPost: Identifiable, Equatable, Hashable {
    static func == (lhs: VPost, rhs: VPost) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id:String
    let objectID:NSManagedObjectID
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
    var isTruncated = false
    var isRepost = false
    var firstQuoteId:String?
        
    var name:String {
        "testttt" // TODO replace with .authorName... emoji check etc
    }
}

class VPostTransformer {
    static let shared = VPostTransformer()
    
    let context:NSManagedObjectContext
    
    init(_ context:NSManagedObjectContext? = nil) {
        self.context = context ?? DataProvider.shared().viewContext
    }
    
    func toVPost(_ mainEvent:Event, skipParents:Bool? = false, plainText:Bool = false) -> VPost? {
        if mainEvent.managedObjectContext == self.context {
            let textRenderer = TextRenderer(self.context, event: mainEvent)
            return VPost(
                id: mainEvent.id,
                objectID: mainEvent.objectID,
                event: mainEvent, // Should always be main context event
                created_at: mainEvent.created_at,
                npub: mainEvent.npub,
                note1: mainEvent.noteId,
                plainText: plainText ? textRenderer.copyPasteText(mainEvent, text: mainEvent.noteText) : "",
                renderedText: textRenderer.renderedText(mainEvent, text: mainEvent.noteText),
                replyingToUsernamesMarkDown: textRenderer.replyingToUsernamesMarkDownString(mainEvent),
                imageUrls: mainEvent.content != nil ? getImgUrlsFromContent(mainEvent.content!) : [],
                displayName: mainEvent.contact?.authorName ?? String((mainEvent.npub.prefix(11))),
                renderedElements: renderElements(mainEvent),
                parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
                threadPostsCount: 1 + mainEvent.parentEvents.count,
                isRepost: mainEvent.isRepost,
                firstQuoteId: mainEvent.firstQuoteId
            )
        }
        
        guard let privateEvent = try? context.existingObject(with: mainEvent.objectID) as? Event else { return nil }
        let textRenderer = TextRenderer(self.context, event: privateEvent)
        return VPost(
            id: privateEvent.id,
            objectID: privateEvent.objectID,
            event: mainEvent, // Should always be main context event
            created_at: privateEvent.created_at,
            npub: privateEvent.npub,
            note1: privateEvent.noteId,
            plainText: plainText ? textRenderer.copyPasteText(privateEvent, text: privateEvent.noteText) : "",
            renderedText: textRenderer.renderedText(privateEvent, text: privateEvent.noteText),
            replyingToUsernamesMarkDown: textRenderer.replyingToUsernamesMarkDownString(privateEvent),
            imageUrls: privateEvent.content != nil ? getImgUrlsFromContent(privateEvent.content!) : [],
            displayName: privateEvent.contact?.authorName ?? String((privateEvent.npub.prefix(11))),
            renderedElements: renderElements(privateEvent),
            parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
            threadPostsCount: 1 + mainEvent.parentEvents.count,
            isRepost: privateEvent.isRepost,
            firstQuoteId: privateEvent.firstQuoteId
        )
    }

    func renderElements(_ event:Event) -> [MarkdownElement] {
        let contentLinkRenderer = TextRenderer(self.context, event: event)
        let input = event.noteTextPrepared
        //        let input = "The quick brown fox jumps over the lazy lazy dog."
        let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp|bmp)(\?\S+){0,1}\b"###
        let videoUrlPattern = ###"(?i)http(s?):\/\/\S+\.(mp4|mov)"###
//        let hashtagPattern = ###"\#\S+"###
        let lightningInvoicePattern = ###"lnbc\S+"###
        let notePattern = ###"nostr:note1[023456789acdefghjklmnpqrstuvwxyz]{58}"###
        let neventPattern = ###"nostr:nevent1[023456789acdefghjklmnpqrstuvwxyz]+\b"###
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
                    let m = matchString.matchingStrings(regex: #"nevent1[023456789acdefghjklmnpqrstuvwxyz]+\b"#)
                    do {
                        let identifier = try ShareableIdentifier(m[0][0])
                        if let noteId = identifier.eventId {
                            result.append(MarkdownElement.noteId(noteId))
                        }
                    }
                    catch {
                        print("problem decoding nevent in event.id: \(event.id)")
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
