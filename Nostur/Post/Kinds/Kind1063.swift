//
//  Kind1063.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

struct Kind1063: View {
    private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    @State private var didStart = false
    @State private var couldBeImposter: Int16 // TODO: this is here but also in NRPostHeaderContainer, need to clean up
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth: CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return fullWidth ? (dim.listWidth - 20) : dim.availableNoteRowWidth }
        
        // DETAIL
        if isDetail && !isReply { return fullWidth ? dim.availablePostDetailRowImageWidth() : dim.availablePostDetailImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    private var fileMetadata: KindFileMetadata
    
    @State var showMiniProfile = false
    
    init(nrPost: NRPost, fileMetadata: KindFileMetadata, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.theme = theme
        self.forceAutoload = forceAutoload
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
        self.fileMetadata = fileMetadata
    }
    
    private var availableWidth: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return dim.listWidth - 20
        }
        
        return dim.availableNoteRowImageWidth()
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
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost))
    }
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: true, theme: theme) {
            
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
                EmbeddedVideoView(url: URL(string: fileMetadata.url)!, pubkey: nrPost.pubkey, nrPost: nrPost, availableWidth: availableWidth + (fullWidth ? +20 : 0), autoload: shouldAutoload, theme: theme, didStart: $didStart)
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
                    availableWidth: availableWidth + (fullWidth ? +20 : 0),
                    maxHeight: 800,
                    contentMode: .fit,
                    autoload: shouldAutoload,
                    isNSFW: nrPost.isNSFW
                )
                .padding(.horizontal, fullWidth ? -10 : 0)
//                SingleMediaViewer(url: URL(string: url)!, pubkey: nrPost.pubkey, imageWidth: availableWidth, fullWidth: fullWidth, autoload: shouldAutoload, theme: theme)
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
