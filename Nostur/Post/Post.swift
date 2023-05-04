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
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let pubkey:String
    let following:Bool
    let id:String
    let objectID:NSManagedObjectID
    let event:Event
    let username:String
    var authorName:String?
    var pictureUrl:String?
    let nip05verified:Bool
    let date:Date
    let ago:String
    let created_at:Int64
    let npub:String
    let note1:String
    var plainText:String
    var renderedText:AttributedString
    var replyingToUsernamesMarkDown:AttributedString? // See ReplyingToFragment
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
    var firstQuote:[VPost]
    var linkPreviewURLs:[URL]
    var liked = false
    var reposted = false
    var replied = false
    
    var isHighlight:Bool
    var highlightAuthorPubkey:String?
    var highlightAuthorPicture:String?
    var highlightAuthorIsFollowing:Bool
    var highlightAuthorName:String?
    var highlightUrl:String?
    
    var missingContacts = false
}

class VPostTransformer {
    static let shared = VPostTransformer()
    
    static let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp)(\?\S+){0,1}\b"###
    static let previewImagePlaceholder = ###"--@!\^@(\d+)@\^!@--"###
    static let videoUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:mp4|mov)(\?\S+){0,1}\b"###
    static let lightningInvoicePattern = ###"(?i)lnbc\S+"###
    static let notePattern = ###"nostr:note1[023456789acdefghjklmnpqrstuvwxyz]{58}"###
    static let neventPattern = ###"nostr:nevent1[023456789acdefghjklmnpqrstuvwxyz]+\b"###
    static let otherUrlsPattern = ###"(?i)(https\:\/\/)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\%\+\.]\@?[\S]+)*\/?[^\s\)]"### // for link previews (TODO: white list domains or not?)
    static let pattern = "\(previewImagePlaceholder)|\(imageUrlPattern)|\(lightningInvoicePattern)|\(notePattern)|\(neventPattern)|\(videoUrlPattern)|\(otherUrlsPattern)"
    static let regex = try! NSRegularExpression(pattern: pattern)
    
    let context:NSManagedObjectContext
    var followingKeys:Set<String>?
    
    init(_ context:NSManagedObjectContext? = nil, followingKeys:Set<String>? = nil) {
        self.context = context ?? DataProvider.shared().viewContext
        self.followingKeys = followingKeys ?? NosturState.shared.followingPublicKeys
    }
    
    func toVPost(_ mainEvent:Event, skipParents:Bool? = false, plainText:Bool = false, forceBg:Bool = false) -> VPost? {
        if !forceBg && Thread.current == Thread.main {
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

            let replyingToMD = textRenderer.replyingToUsernamesMarkDownString(mainEvent)
            
            return VPost(
                pubkey: mainEvent.pubkey,
                following:isFollowedByCurrentAccount(mainEvent),
                id: mainEvent.id,
                objectID: mainEvent.objectID,
                event: mainEvent, // Should always be main context event
                username: mainEvent.username,
                authorName: mainEvent.contact?.authorName,
                pictureUrl: mainEvent.contact?.picture,
                nip05verified:mainEvent.contact?.nip05veried ?? false,
                date: mainEvent.date,
                ago: mainEvent.ago,
                created_at: mainEvent.created_at,
                npub: mainEvent.npub,
                note1: mainEvent.noteId,
                plainText: plainText ? textRenderer.copyPasteText(mainEvent, text: mainEvent.noteText) : "",
                renderedText: textRenderer.renderedText(mainEvent, text: mainEvent.noteText),
                replyingToUsernamesMarkDown: replyingToMD != nil ? try! AttributedString(markdown: replyingToMD!) : nil,
                imageUrls: mainEvent.content != nil ? getImgUrlsFromContent(mainEvent.content!) : [],
                displayName: mainEvent.contact?.authorName ?? String((mainEvent.npub.prefix(11))),
                renderedElements: renderedForRow,
                renderedElementsDetail: renderedElements,
                parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true) } : [],
                threadPostsCount: 1 + mainEvent.parentEvents.count,
                isRepost: mainEvent.isRepost,
                firstQuoteId: mainEvent.firstQuoteId,
                firstQuote: mainEvent.firstQuote != nil ? [toVPost(mainEvent.firstQuote!, skipParents: true)].compactMap { $0 } : [],
                linkPreviewURLs: linkPreviewURLs,
                liked: likedByCurrentAccount(mainEvent),
                reposted: repostedByCurrentAccount(mainEvent),
                replied: repliedByCurrentAccount(mainEvent),
                
                // Ughhh this needs clean up and put somewhere else probably
                isHighlight: mainEvent.kind == 9802,
                highlightAuthorPubkey: mainEvent.kind == 9802 ? mainEvent.fastTags.first(where: { $0.0 == "p" } )?.1 : nil,
                highlightAuthorPicture: mainEvent.kind == 9802 ? mainEvent.contacts?.first?.picture : nil,
                highlightAuthorIsFollowing: mainEvent.kind == 9802 ? isFollowedByCurrentAccount(mainEvent.fastTags.first(where: { $0.0 == "p" } )?.1) : false,
                highlightAuthorName: mainEvent.kind == 9802 ? mainEvent.contacts?.first?.authorName : nil,
                highlightUrl: mainEvent.kind == 9802 ? mainEvent.fastTags.first(where: { $0.0 == "r" } )?.1 : nil,
                
                missingContacts: (mainEvent.contacts?.count ?? 0) < mainEvent.fastTags.filter({ $0.0 == "p" }).count
            )
        }
        else {
            guard let privateEvent = context.object(with: mainEvent.objectID) as? Event else { return nil }
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
            
            var actualMainEvent:Event?
            let eventId = privateEvent.id
            DataProvider.shared().viewContext.performAndWait {
                actualMainEvent = try? Event.fetchEvent(id: eventId, context: DataProvider.shared().viewContext)
//                actualMainEvent = try? DataProvider.shared().viewContext.existingObject(with: privateEvent.objectID) as? Event
            }
            
            guard actualMainEvent != nil else { return nil }
            
            let replyingToMD = textRenderer.replyingToUsernamesMarkDownString(privateEvent)
            
            return VPost(
                pubkey: privateEvent.pubkey,
                following:isFollowedByCurrentAccount(privateEvent),
                id: privateEvent.id,
                objectID: privateEvent.objectID,
                event: actualMainEvent!, // Should always be main context event
                username: privateEvent.username,
                authorName: privateEvent.contact?.authorName,
                pictureUrl: privateEvent.contact?.picture,
                nip05verified: privateEvent.contact?.nip05veried ?? false,
                date: privateEvent.date,
                ago: privateEvent.ago,
                created_at: privateEvent.created_at,
                npub: privateEvent.npub,
                note1: privateEvent.noteId,
                plainText: plainText ? textRenderer.copyPasteText(privateEvent, text: privateEvent.noteText) : "",
                renderedText: textRenderer.renderedText(privateEvent, text: privateEvent.noteText),
                replyingToUsernamesMarkDown: replyingToMD != nil ? try! AttributedString(markdown: replyingToMD!) : nil,
                imageUrls: privateEvent.content != nil ? getImgUrlsFromContent(privateEvent.content!) : [],
                displayName: privateEvent.contact?.authorName ?? String((privateEvent.npub.prefix(11))),
                renderedElements: renderedForRow,
                renderedElementsDetail: renderedElements,
                parentPosts: !skipParents! ? mainEvent.parentEvents.compactMap { toVPost($0, skipParents: true, forceBg: forceBg) } : [],
                threadPostsCount: 1 + mainEvent.parentEvents.count,
                isRepost: privateEvent.isRepost,
                firstQuoteId: privateEvent.firstQuoteId,
                firstQuote: privateEvent.firstQuote != nil ? [toVPost(privateEvent.firstQuote!, skipParents: true)].compactMap { $0 } : [],
                linkPreviewURLs: linkPreviewURLs,
                liked: likedByCurrentAccount(privateEvent),
                reposted: repostedByCurrentAccount(privateEvent),
                replied: repliedByCurrentAccount(privateEvent),
                
                // Ughhh this needs clean up and put somewhere else probably
                isHighlight: privateEvent.kind == 9802,
                highlightAuthorPubkey: privateEvent.kind == 9802 ? privateEvent.fastTags.first(where: { $0.0 == "p" } )?.1 : nil,
                highlightAuthorPicture: privateEvent.kind == 9802 ? privateEvent.contacts?.first?.picture : nil,
                highlightAuthorIsFollowing: privateEvent.kind == 9802 ? isFollowedByCurrentAccount(privateEvent.fastTags.first(where: { $0.0 == "p" } )?.1) : false,
                highlightAuthorName: privateEvent.kind == 9802 ? privateEvent.contacts?.first?.authorName : nil,
                highlightUrl: privateEvent.kind == 9802 ? privateEvent.fastTags.first(where: { $0.0 == "r" } )?.1 : nil,
                
                missingContacts: (privateEvent.contacts?.count ?? 0) < privateEvent.fastTags.filter({ $0.0 == "p" }).count
            )
        }
    }
    
    func likedByCurrentAccount(_ event:Event) -> Bool {
        guard let ctx = event.managedObjectContext else { return false }
        let fr = Event.fetchRequest()
        // TODO: Maybe add > .created_at, faster or not?
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
    
    func repliedByCurrentAccount(_ event:Event) -> Bool {
        guard let ctx = event.managedObjectContext else { return false }
        let fr = Event.fetchRequest()
        // TODO: Maybe add > .created_at, faster or not?
        fr.predicate = NSPredicate(format: "replyToId == %@ AND pubkey == %@",
                                   event.id, NosturState.shared.activeAccountPublicKey)
        fr.fetchLimit = 1
        fr.resultType = .countResultType
        
        return ctx.performAndWait {
            let count = (try? ctx.count(for: fr)) ?? 0
            return count > 0
        }
    }
    
    func isFollowedByCurrentAccount(_ event:Event) -> Bool {
        return followingKeys?.contains(event.pubkey) ?? false
    }
    
    func isFollowedByCurrentAccount(_ pubkey:String?) -> Bool {
        guard let pubkey_ = pubkey else { return false }
        return followingKeys?.contains(pubkey_) ?? false
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
        if Thread.isMainThread {
            print("☠️☠️☠️☠️ renderElements on MAIN thread....")
        }
        let contentLinkRenderer = TextRenderer(self.context, event: event)
        let input = event.noteTextPrepared
        
        
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [MarkdownElement] = []
        var linkPreviewUrls: [URL] = []
        var lastMatchEnd = 0
        
        Self.regex.enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:nonMatch)))
                
                if matchString.matchingStrings(regex: Self.imageUrlPattern).count > 0 {
                    if let url = URL(string: matchString) {
                        result.append(MarkdownElement.image(url))
                    }
                    else {
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: Self.videoUrlPattern).count > 0 {
                    if let url = URL(string: matchString) {
                        result.append(MarkdownElement.video(url))
                    }
                    else {
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: Self.otherUrlsPattern).count > 0 {
                    if let url = URL(string: matchString) {
                        result.append(MarkdownElement.linkPreview(url))
                        linkPreviewUrls.append(url)
                    }
                    else {
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: Self.notePattern).count > 0 {
                    let note1String = String(matchString.dropFirst(6)) // drop nostr:
                    result.append(MarkdownElement.note1(note1String))
                }
                else if matchString.matchingStrings(regex: Self.previewImagePlaceholder).count > 0 {
                    let m = matchString.matchingStrings(regex: Self.previewImagePlaceholder)
                    if let p = event.previewImages[safe: Int(m[0][0])] {
                        result.append(MarkdownElement.postPreviewImage(p))
                    }
                }
                else if matchString.matchingStrings(regex: Self.neventPattern).count > 0 {
                    let nevent1String = String(matchString.dropFirst(6)) // drop "nostr:"
                    do {
                        let identifier = try ShareableIdentifier(nevent1String)
                        if let noteHex = identifier.eventId { // .eventId is already hex
                            result.append(MarkdownElement.noteHex(noteHex))
                        }
                    }
                    catch {
                        print("problem decoding nevent in event.id: \(event.id)")
                        result.append(MarkdownElement.text(contentLinkRenderer.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: Self.lightningInvoicePattern).count > 0 {
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
    case noteHex(String)
    case lnbc(String)
    case link(String, URL)
    case image(URL)
    case video(URL)
    case linkPreview(URL)
    case postPreviewImage(UIImage)
}
