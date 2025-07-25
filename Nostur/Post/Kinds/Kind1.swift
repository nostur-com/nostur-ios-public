//
//  Kind1.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind1: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
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
    
    
    private var availableWidth: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return dim.listWidth - 20
        }
        
        return dim.availableNoteRowImageWidth()
    }
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var showMiniProfile = false
    @State var clipBottomHeight: CGFloat = 900.0
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false, theme: Theme) {
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
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth || isOlasGeneric, forceAutoload: forceAutoload, theme: theme) { 
            if (isDetail) {
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                
//                Color.purple
//                    .frame(height: 30)
//                    .overlay { Text(availableWidth.description) }
//                    .debugDimensions("Kind1.normalView")
                
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: isDetail, fullWidth: fullWidth, availableWidth: availableWidth, forceAutoload: forceAutoload, theme: theme)
                    .frame(maxWidth: .infinity, alignment:.leading)
            }
            else {
                
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                
//                Color.purple
//                    .frame(height: 30)
//                    .overlay { Text(availableWidth.description) }
//                    .debugDimensions("Kind1.normalView2")
                
                ContentRenderer(nrPost: nrPost, showMore: $showMore, isDetail: isDetail, fullWidth: fullWidth, availableWidth: availableWidth, forceAutoload: forceAutoload, theme: theme)
//                    .fixedSize(horizontal: false, vertical: true) // <-- this or child .fixedSizes will try to render outside frame and cutoff (because clipped() below)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: clipBottomHeight, alignment: .top)
                    .clipBottom(height: clipBottomHeight)
                    .overlay(alignment: .bottomTrailing) {
                        if (nrPost.previewWeights?.moreItems ?? false) && !showMore {
                            Button {
                                showMore = true
                                clipBottomHeight = 18000.0
                            } label: {
                                Text("Read more...")
                                    .foregroundColor(theme.primary)
                                    .fontWeightBold()
                                    .padding(5)
                                    .background(theme.accent)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, theme: theme) {
            
            if missingReplyTo {
                ReplyingToFragmentView(nrPost: nrPost, theme: theme)
            }
            if let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
            }
            if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                Image(systemName: "exclamationmark.triangle.fill")
            }
            
            ContentRenderer(nrPost: nrPost, showMore: $showMore,  isDetail: false, fullWidth: fullWidth, availableWidth: availableWidth, forceAutoload: shouldAutoload, theme: theme)
        }
    }
}
