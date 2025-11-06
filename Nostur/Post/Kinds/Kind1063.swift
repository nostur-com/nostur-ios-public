//
//  Kind1063.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

struct Kind1063: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
        
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth: CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return fullWidth ? (availableWidth - 20) : DIMENSIONS.availableNoteRowWidth(availableWidth) }
        
        // DETAIL
        if isDetail && !isReply { return fullWidth ? DIMENSIONS.availablePostDetailRowImageWidth(availableWidth) : availableWidth }
        
        // DETAIL PARENT OR REPLY
        return DIMENSIONS.availablePostDetailRowImageWidth(availableWidth)
    }
    
    private var fileMetadata: KindFileMetadata
    
    @State var showMiniProfile = false
    
    init(nrPost: NRPost, fileMetadata: KindFileMetadata, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.forceAutoload = forceAutoload
        self.fileMetadata = fileMetadata
    }
    
    private var availableWidth_: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return availableWidth - 20
        }
        
        return DIMENSIONS.availableNoteRowImageWidth(availableWidth)
    }
    
    var body: some View {
        if isEmbedded {
            self.embeddedView
        }
        else {
            self.normalView
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: true) {
            
            content
            
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        content
    }
    
    
    @ViewBuilder 
    var content: some View {
        VStack(alignment: .leading) {
            if isDetail, let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
                    
            }
            if is1063Video(nrPost) {
                EmbeddedVideoView(url: URL(string: fileMetadata.url)!, pubkey: nrPost.pubkey, nrPost: nrPost, autoload: shouldAutoload)
                    .environment(\.availableWidth, availableWidth_ + (fullWidth ? +20 : 0))
                    .padding(.horizontal, fullWidth ? -10 : 0)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
//                    .withoutAnimation()
            }
            else {
                MediaContentView(
                    galleryItem: GalleryItem(
                        url: URL(string: fileMetadata.url)!,
                        pubkey: nrPost.pubkey,
                        eventId: nrPost.id,
                        dimensions: fileMetadata.size,
                        blurhash: fileMetadata.blurhash
                    ),
                    availableWidth: availableWidth_ + (fullWidth ? +20 : 0),
                    maxHeight: 800,
                    contentMode: .fit,
                    autoload: shouldAutoload,
                    isNSFW: nrPost.isNSFW
                )
                .padding(.horizontal, fullWidth ? -10 : 0)
//                SingleMediaViewer(url: URL(string: url)!, pubkey: nrPost.pubkey, imageWidth: availableWidth_, fullWidth: fullWidth, autoload: shouldAutoload)
//                    .padding(.horizontal, fullWidth ? -10 : 0)
////                    .padding(.horizontal, -10)
////                    .fixedSize(horizontal: false, vertical: true)
//                    .padding(.vertical, 10)
//                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
}


struct KindFileMetadata {
    var url:String
    var m:String?
    var hash:String?
    var dim:String?
    var blurhash:String?
    
    var size: CGSize? {
        guard let dim else { return nil }
        let parts = dim.split(separator: "x", maxSplits: 1)
        if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
            return CGSize(width: width, height: height)
        }
        return nil
    }
    
    var aspect: CGFloat {
        if let size = size {
            return size.height / size.width
        } else {
            return 1.0
        }
    }
}


func canRender1063(_ nrPost:NRPost) -> Bool {
    guard nrPost.kind == 1063 else { return false }
    guard let hl = nrPost.fileMetadata else { return false }
    
    guard let mTag = hl.m else { return false }
    guard !hl.url.isEmpty else { return false }
    guard ["video/mp4", "video/quicktime", "image/png", "image/jpg", "image/jpeg", "image/gif", "image/webp", "image/avif"].contains(mTag) else { return false }
    return true
}

func is1063Video(_ nrPost:NRPost) -> Bool {
    guard nrPost.kind == 1063 else { return false }
    guard let hl = nrPost.fileMetadata else { return false }
    
    guard let mTag = hl.m else { return false }
    guard !hl.url.isEmpty else { return false }
    guard ["video/mp4", "video/quicktime"].contains(mTag) else { return false }
    return true
}
