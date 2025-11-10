//
//  Kind1.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind1: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @State private var showMore = false
    
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
    
    
    private var availableWidth_: CGFloat { // dim.listWidth is now .availableWidth, so now this one is .availableWidth_
        if isDetail || fullWidth || isEmbedded {
            return availableWidth - 20
        }
        
        return DIMENSIONS.availableNoteRowImageWidth(availableWidth)
    }
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var showMiniProfile = false
    @State var clipBottomHeight: CGFloat = 900.0
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil,
         isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false,
         forceAutoload: Bool = false) {
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
//        _clipBottomHeight = State(wrappedValue: isEmbedded ? 300.0 : 900.0)
    }
    
    var body: some View {
        if nrPost.plainTextOnly {
            Text("TODO PLAINTEXTONLY") // TODO: PLAIN TEXTO ONLY
        }
        else if isEmbedded {
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
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply,
                   isDetail: isDetail, fullWidth: fullWidth || isOlasGeneric, forceAutoload: forceAutoload, nxViewingContext: nxViewingContext, containerID: containerID, theme: theme, availableWidth: availableWidth) {
            if (isDetail) {
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                
//                Color.purple
//                    .frame(height: 30)
//                    .overlay { Text(availableWidth_.description) }
//                    .debugDimensions("Kind1.normalView")
                
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload)
                    .environment(\.availableWidth, availableWidth_)
                    .frame(maxWidth: .infinity, alignment:.leading)
            }
            else {
                
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                
//                Color.purple
//                    .frame(height: 30)
//                    .overlay { Text(availableWidth_.description) }
//                    .debugDimensions("Kind1.normalView2")
                
                ContentRenderer(nrPost: nrPost, showMore: $showMore, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload)
                    .environment(\.availableWidth, availableWidth_)
//                    .fixedSize(horizontal: false, vertical: true) // <-- this or child .fixedSizes will try to render outside frame and cutoff (because clipped() below)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: clipBottomHeight, alignment: .top)
                    .clipBottom(height: clipBottomHeight)
                    .overlay(alignment: .bottomTrailing) {
                        if (nrPost.previewWeights?.moreItems ?? false) && !showMore {
                            Image(systemName: "chevron.compact.down")
                                .foregroundColor(.white)
                                .padding(5)
                                .padding(.top, 5)
                                .background {
                                    RoundedRectangle(cornerRadius: 5)
                                        .foregroundColor(theme.accent)
                                }
                                .contentShape(Rectangle())
                                .highPriorityGesture(TapGesture().onEnded {
                                    showMore = true
                                    clipBottomHeight = 28000.0
                                })                            
                        }
                    }
//                    .overlay(alignment: .topLeading) {
//                        Button("WW") {
//                            print("previewWeights.posts: \(String(describing: nrPost.previewWeights?.posts))")
//                            print("previewWeights.videos: \(String(describing: nrPost.previewWeights?.videos))")
//                            print("previewWeights.pictures: \(String(describing: nrPost.previewWeights?.pictures))")
//                            print("previewWeights.linkPreviews: \(String(describing: nrPost.previewWeights?.linkPreviews))")
//                            print("previewWeights.text: \(String(describing: nrPost.previewWeights?.text))")
//                            print("previewWeights.other: \(String(describing: nrPost.previewWeights?.other))")
//                            
//                            print("previewWeights.morePosts: \(String(describing: nrPost.previewWeights?.morePosts))")
//                            print("previewWeights.moreVideos: \(String(describing: nrPost.previewWeights?.moreVideos))")
//                            print("previewWeights.morePictures: \(String(describing: nrPost.previewWeights?.morePictures))")
//                            print("previewWeights.linkPreviews: \(String(describing: nrPost.previewWeights?.linkPreviews))")
//                            print("previewWeights.moreText: \(String(describing: nrPost.previewWeights?.moreText))")
//                            print("previewWeights.moreOther: \(String(describing: nrPost.previewWeights?.moreOther))")
//                            
//                            
//                            print("previewWeights.morePosts: \(String(describing: nrPost.previewWeights?.morePosts))")
//                            print("previewWeights.weight: \(String(describing: nrPost.previewWeights?.weight))")
//                            
//                            print("nrPost.sizeEstimate.rawValue: \(String(describing: nrPost.sizeEstimate.rawValue))")
//                            print("previewWeights.textOnly: \(String(describing: nrPost.previewWeights?.textOnly))")
//                        }
//                        .background(Color.red)
//                    }
            }
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            
            if missingReplyTo {
                ReplyingToFragmentView(nrPost: nrPost)
            }
            if let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
            }
            if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                Image(systemName: "exclamationmark.triangle.fill")
            }
            
            ContentRenderer(nrPost: nrPost, showMore: $showMore,  isDetail: false, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                .environment(\.availableWidth, availableWidth_)
                .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: clipBottomHeight, alignment: .top)
                .clipBottom(height: clipBottomHeight)
                .overlay(alignment: .bottomTrailing) {
                    if (nrPost.previewWeights?.moreItems ?? false) && !showMore {
                        Image(systemName: "chevron.compact.down")
                            .foregroundColor(.white)
                            .padding(5)
                            .padding(.top, 5)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .foregroundColor(theme.accent)
                            }
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded {
                                showMore = true
                                clipBottomHeight = 28000.0
                            })
                    }
                }
        }
    }
}
