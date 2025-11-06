//
//  Kind20.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind20: View {
    @Environment(\.nxEnv) private var nxEnv
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
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var showMiniProfile = false
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
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
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxEnv.nxViewingContext.contains(.screenshot))
    }
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: true, forceAutoload: true) {
            
            if isDetail {
                detailContent
            }
            else {
                rowContent
            }
            
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            rowContent
        }
    }
    
    @ViewBuilder
    private var rowContent: some View {
        if let galleryItem = nrPost.galleryItems.first {
            VStack {
                    MediaContentView(
                        galleryItem: galleryItem,
                        availableWidth: availableWidth,
                        placeholderAspect: 1.0,
                        maxHeight: 800,
                        contentMode: .fit,
                        galleryItems: nrPost.galleryItems,
                        autoload: shouldAutoload,
                        isNSFW: nrPost.isNSFW
                    )
                    .padding(.horizontal, -10)
                    .overlay(alignment: .bottomTrailing) {
                        if nrPost.galleryItems.count > 1 {
                            Text("\(nrPost.galleryItems.count - 1) more")
                                .fontWeightBold()
                                .foregroundColor(.white)
                                .padding(5)
                                .background(.black)
                                .allowsHitTesting(false)
                        }
                    }
                
                
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: false, fullWidth: true, forceAutoload: shouldAutoload)
                    .environment(\.availableWidth, DIMENSIONS.availableNoteRowImageWidth(availableWidth))
                    .padding(.vertical, 10)
            }
        }
        else {
            EmptyView()
        }
    }
    
    
    @ViewBuilder // When there are multiple images, put the text at the top
    private var detailContent: some View {
        VStack {
            if nrPost.galleryItems.count > 1 {
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: true, fullWidth: settings.fullWidthImages)
                    .environment(\.availableWidth, availableWidth - 20)
                    .padding(.top, 10)
            }
            ForEach(nrPost.galleryItems) { galleryItem in
                MediaContentView(
                    galleryItem: galleryItem,
                    availableWidth: availableWidth,
                    placeholderAspect: 1.0,
                    contentMode: .fit,
                    galleryItems: nrPost.galleryItems,
                    autoload: true // We opened detail, so can autoload
                )
                .padding(.top, 10)
                .padding(.horizontal, -10)
            }
            
            if nrPost.galleryItems.count < 2 {
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: true, fullWidth: settings.fullWidthImages)
                    .environment(\.availableWidth, availableWidth - 20)
                    .padding(.vertical, 10)
            }
        }
    }
}
