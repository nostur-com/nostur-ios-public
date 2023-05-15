//
//  Post.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import Foundation
import CoreData
import UIKit
import Combine

//struct VPost: Identifiable, Equatable, Hashable {
//    static func == (lhs: VPost, rhs: VPost) -> Bool {
//        lhs.id == rhs.id
//    }
//
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//    }
//
//    let pubkey:String
//    let following:Bool
//    let id:String
//    let objectID:NSManagedObjectID
//    let event:Event
//    let username:String
//    var authorName:String?
//    var pictureUrl:String?
//    let nip05verified:Bool
//    let date:Date
//    let ago:String
//    let created_at:Int64
//    let npub:String
//    let note1:String
//    var plainText:String
//    var renderedText:AttributedString
//    var replyingToUsernamesMarkDown:AttributedString? // See ReplyingToFragment
//    var imageUrls:[URL] // See ImageViewer
//    var displayName:String
//
//    var renderedElements:[ContentElement] // NoteRow.Kind1
//    var renderedElementsDetail:[ContentElement] // PostDetail.Kind1
//
//    var parentPosts:[VPost]
//
//    // This one event + parents are shown as a single Thread, coming from a single nrPost
//    // So to get the counter correct we can no longer just do vPosts.count
//    // We need vPosts.reduce ... .parentPosts.count
//    var threadPostsCount:Int
//    var isTruncated = false
//    var isRepost = false
//    var replyToId:String?
//    var firstQuoteId:String?
//    var firstQuote:[VPost]
//    var linkPreviewURLs:[URL]
//    var liked = false
//    var reposted = false
//    var replied = false
//
//    var isHighlight:Bool
//    var highlightAuthorPubkey:String?
//    var highlightAuthorPicture:String?
//    var highlightAuthorIsFollowing:Bool
//    var highlightAuthorName:String?
//    var highlightUrl:String?
//
//    var missingContacts = false
//}

class VPostTransformer {
    static let imageUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:png|jpe?g|gif|webp)(\?\S+){0,1}\b"###
    static let previewImagePlaceholder = ###"--@!\^@(\d+)@\^!@--"###
    static let videoUrlPattern = ###"(?i)https?:\/\/\S+?\.(?:mp4|mov)(\?\S+){0,1}\b"###
    static let lightningInvoicePattern = ###"(?i)lnbc\S+"###
    static let notePattern = ###"nostr:note1[023456789acdefghjklmnpqrstuvwxyz]{58}"###
    static let neventPattern = ###"nostr:nevent1[023456789acdefghjklmnpqrstuvwxyz]+\b"###
    static let nprofilePattern = ###"nostr:nprofile1[023456789acdefghjklmnpqrstuvwxyz]+\b"###
    static let otherUrlsPattern = ###"(?i)(https\:\/\/)[a-zA-Z0-9\-\.]+(?:\.[a-zA-Z]{2,999}+)+([\/\?\=\&\#\%\+\.]\@?[\S]+)*\/?[^\s\)]"### // for link previews (TODO: white list domains or not?)
    static let pattern = "\(previewImagePlaceholder)|\(imageUrlPattern)|\(lightningInvoicePattern)|\(notePattern)|\(nprofilePattern)|\(neventPattern)|\(videoUrlPattern)|\(otherUrlsPattern)"
    static let regex = try! NSRegularExpression(pattern: pattern)
}

public typealias Ptag = String

enum ContentElement: Hashable {
//    case rendered(String)
//    case plain(String)
    case text(AttributedStringWithPs, String)
    case note1(String)
    case noteHex(String)
    case lnbc(String)
    case link(String, URL)
    case image(URL)
    case video(URL)
    case linkPreview(URL)
    case postPreviewImage(UIImage)
    case nevent1(ShareableIdentifier)
    case nprofile1(ShareableIdentifier)
}

struct AttributedStringWithPs: Hashable {
    var text:AttributedString
    var pTags:[Ptag]
    var event:Event
}
