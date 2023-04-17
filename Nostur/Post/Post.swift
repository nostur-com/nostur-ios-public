//
//  Post.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import Foundation
import CoreData
import UIKit
//import Combine

struct VPost: Identifiable, Equatable, Hashable {
    static func == (lhs: VPost, rhs: VPost) -> Bool {
        lhs.id == rhs.id
//        && lhs.replyingToUsernamesMarkDown == rhs.replyingToUsernamesMarkDown
//        && lhs.renderedText == rhs.renderedText
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
//        hasher.combine(renderedText)
//        hasher.combine(replyingToUsernamesMarkDown)
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
    
    var renderedElements:[MarkdownElement] // NoteRow.Kind1
    var renderedElementsDetail:[MarkdownElement] // PostDetail.Kind1
    
    var parentPosts:[VPost]
    
    // This one event + parents are shown as a single Thread, coming from a single vPost
    // So to get the counter correct we can no longer just do vPosts.count
    // We need vPosts.reduce ... .parentPosts.count
    var threadPostsCount:Int
    var isTruncated = false
    var isRepost = false
    var firstQuoteId:String?
    var linkPreviewURLs:[URL]
    var liked = false
    var reposted = false
//    var subscriptions = Set<AnyCancellable>()
    
//    init(id: String, objectID: NSManagedObjectID, event: Event, created_at: Int64, npub: String, note1: String, plainText: String, renderedText: AttributedString, replyingToUsernamesMarkDown: String? = nil, imageUrls: [URL], displayName: String, renderedElements: [MarkdownElement], parentPosts: [VPost], threadPostsCount: Int, isTruncated: Bool = false, isRepost: Bool = false, firstQuoteId: String? = nil) {
//        self.id = id
//        self.objectID = objectID
//        self.event = event
//        self.created_at = created_at
//        self.npub = npub
//        self.note1 = note1
//        self.plainText = plainText
//        self.renderedText = renderedText
//        self.replyingToUsernamesMarkDown = replyingToUsernamesMarkDown
//        self.imageUrls = imageUrls
//        self.displayName = displayName
//        self.renderedElements = renderedElements
//        self.parentPosts = parentPosts
//        self.threadPostsCount = threadPostsCount
//        self.isTruncated = isTruncated
//        self.isRepost = isRepost
//        self.firstQuoteId = firstQuoteId
//
//        self.event.objectWillChange
//            .sink { [weak self] in
//                guard let self = self else { return }
//                let textRenderer = TextRenderer(self.event.managedObjectContext, event: self.event)
//                let transformer = VPostTransformer.shared
//
//                self.renderedText = textRenderer.renderedText(self.event, text: self.event.noteText)
//                self.replyingToUsernamesMarkDown = textRenderer.replyingToUsernamesMarkDownString(self.event)
//                self.displayName = self.event.contact?.authorName ?? String((self.event.npub.prefix(11)))
//                self.renderedElements = transformer.renderElements(self.event)
////                self.parentPosts = !skipParents! ? self.event.parentEvents.compactMap { toVPost($0, skipParents: true) } : []
////                self.threadPostsCount = 1 + self.event.parentEvents.count
//            }
//            .store(in: &subscriptions)
//    }
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
            let (renderedElements, linkPreviewURLs) = renderElements(mainEvent)
            
            let firstQuote = renderedElements.first(where: { element in
                    if case .note1 = element {
                        return true
                    }
                    return false
            })
            
            var renderedForRow:[MarkdownElement] {
                var gotVideo = false
                return renderedElements
                    .filter { element in
                        if case .video = element {
                            if (!gotVideo) {
                                gotVideo = true
                                return true
                            }
                            return false
                        }
                        if case .note1 = element {
                            return element == firstQuote
                        }
                        else {
                            return true
                        }
                    }
            }

            
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
                renderedElements: renderedForRow,
                renderedElementsDetail: renderedElements,
                parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
                threadPostsCount: 1 + mainEvent.parentEvents.count,
                isRepost: mainEvent.isRepost,
                firstQuoteId: mainEvent.firstQuoteId,
                linkPreviewURLs: linkPreviewURLs,
                liked: likedByCurrentAccount(mainEvent),
                reposted: repostedByCurrentAccount(mainEvent)
            )
        }
        
        guard let privateEvent = try? context.existingObject(with: mainEvent.objectID) as? Event else { return nil }
        let textRenderer = TextRenderer(self.context, event: privateEvent)
        let (renderedElements, linkPreviewURLs) = renderElements(privateEvent)
        
        let firstQuote = renderedElements.first(where: { element in
                if case .note1 = element {
                    return true
                }
                return false
        })
        
        var renderedForRow:[MarkdownElement] {
            var gotVideo = false
            return renderedElements
                .filter { element in
                    if case .video = element {
                        if (!gotVideo) {
                            gotVideo = true
                            return true
                        }
                        return false
                    }
                    if case .note1 = element {
                        return element == firstQuote
                    }
                    else {
                        return true
                    }
                }
        }
        
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
            renderedElements: renderedForRow,
            renderedElementsDetail: renderedElements,
            parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
            threadPostsCount: 1 + mainEvent.parentEvents.count,
            isRepost: privateEvent.isRepost,
            firstQuoteId: privateEvent.firstQuoteId,
            linkPreviewURLs: linkPreviewURLs,
            liked: likedByCurrentAccount(privateEvent),
            reposted: repostedByCurrentAccount(privateEvent)
        )
    }
    
    func likedByCurrentAccount(_ event:Event) -> Bool {
        guard let ctx = event.managedObjectContext else { return false }
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "reactionToId == %@ AND pubkey == %@ AND kind == 7",
                                   event.id, NosturState.shared.activeAccountPublicKey)
        fr.fetchLimit = 1
        fr.resultType = .countResultType
        
        //TODO: should check for "+","👍","🤙","❤️","🫂","🤗","😘","😍","💯","🤩","⚡️","🔥","💥","🚀"
        
        return ctx.performAndWait {
            let count = (try? ctx.count(for: fr)) ?? 0
            return count > 0
        }
    }
    
    func repostedByCurrentAccount(_ event:Event) -> Bool {
        guard let ctx = event.managedObjectContext else { return false }
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "repostForId == %@ AND pubkey == %@",
                                   event.id, NosturState.shared.activeAccountPublicKey)
        fr.fetchLimit = 1
        fr.resultType = .countResultType
        
        return ctx.performAndWait {
            let count = (try? ctx.count(for: fr)) ?? 0
            return count > 0
        }
    }

    func renderElements(_ event:Event) -> ([MarkdownElement], [URL]) {
        let contentLinkRenderer = TextRenderer(self.context, event: event)
        let input = event.noteTextPrepared
        let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp)(\?\S+){0,1}\b"###
        let previewImagePlaceholder = ###"--@!\^@(\d+)@\^!@--"###
        let videoUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:mp4|mov)(\?\S+){0,1}\b"###
        let lightningInvoicePattern = ###"(?i)lnbc\S+"###
        let notePattern = ###"nostr:note1[023456789acdefghjklmnpqrstuvwxyz]{58}"###
        let neventPattern = ###"nostr:nevent1[023456789acdefghjklmnpqrstuvwxyz]+\b"###
        let otherUrlsPattern = ###"(?i)(https\:\/\/)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\%\+\.]\@?[\S]+)*\/?"### // for link previews (TODO: white list domains or not?)
        let pattern = "\(previewImagePlaceholder)|\(imageUrlPattern)|\(lightningInvoicePattern)|\(notePattern)|\(neventPattern)|\(videoUrlPattern)|\(otherUrlsPattern)"
        
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [MarkdownElement] = []
        var linkPreviewUrls: [URL] = []
        var lastMatchEnd = 0
        
        regex.enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:nonMatch)))
                
                if matchString.matchingStrings(regex: imageUrlPattern).count > 0 {
                    if let url = URL(string: matchString) {
                        result.append(MarkdownElement.image(url))
                    }
                    else {
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: videoUrlPattern).count > 0 {
                    if let url = URL(string: matchString) {
                        result.append(MarkdownElement.video(url))
                    }
                    else {
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: otherUrlsPattern).count > 0 {
                    if let url = URL(string: matchString) {
                        result.append(MarkdownElement.linkPreview(url))
                        linkPreviewUrls.append(url)
                    }
                    else {
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: notePattern).count > 0 {
                    let m = matchString.matchingStrings(regex:#"note1[023456789acdefghjklmnpqrstuvwxyz]{58}"#)
                    result.append(MarkdownElement.note1(m[0][0]))
                }
                else if matchString.matchingStrings(regex: previewImagePlaceholder).count > 0 {
                    let m = matchString.matchingStrings(regex:previewImagePlaceholder)
                    if let p = event.previewImages[safe: Int(m[0][0])] {
                        result.append(MarkdownElement.postPreviewImage(p))
                    }
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
        
        return (result, linkPreviewUrls)
    }
}


enum MarkdownElement: Hashable {
//    case rendered(String)
//    case plain(String)
    case text(AttributedString)
    case note1(String)
    case noteId(String)
    case lnbc(String)
    case link(String, URL)
    case image(URL)
    case video(URL)
    case linkPreview(URL)
    case postPreviewImage(UIImage)
}
