//
//  Kind9802.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind9802: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @ObservedObject private var highlightAttributes: HighlightAttributes
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    
    private var availableWidth: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return dim.listWidth - 20
        }
        
        return dim.availableNoteRowImageWidth()
    }
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, forceAutoload: Bool = false) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.highlightAttributes = nrPost.highlightAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
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
        
        
        if let hlAuthorPubkey = highlightAttributes.authorPubkey, hlAuthorPubkey == nrPost.pubkey {
            // No need to wrap in PostEmbeddedLayout if the 9802.pubkey is the same as quoted text pubkey
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateTo(nrPost, context: dim.id)
                }
        }
        else {
            PostEmbeddedLayout(nrPost: nrPost) {
                
                content
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !nxViewingContext.contains(.preview) else { return }
                        navigateTo(nrPost, context: dim.id)
                    }
                
            }
        }
    }
    
    @ViewBuilder
    var content: some View {
        
        // Comment on quote from "comment" tag
        ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: isDetail, fullWidth: fullWidth, availableWidth: availableWidth, forceAutoload: forceAutoload)
            .frame(maxWidth: .infinity, alignment:.leading)
        
        // The highlight, from .content
        VStack {
            Text(nrPost.content ?? "")
                .lineLimit(isDetail ? 500 : 25)
                .fixedSize(horizontal: false, vertical: true)
                .fontItalic()
                .padding(20)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    if let firstE = nrPost.firstE {
                        navigateTo(NotePath(id: firstE), context: dim.id)
                    }
                    else if let aTag = nrPost.fastTags.first(where: { $0.0 == "a" }),
                            let naddr = try? ShareableIdentifier(aTag: aTag.1) {
                            navigateTo(Naddr1Path(naddr1: naddr.bech32string), context: dim.id)
                    }
                }
                .overlay(alignment:.topLeading) {
                    Image(systemName: "quote.opening")
                        .foregroundColor(Color.secondary)
                }
                .overlay(alignment:.bottomTrailing) {
                    Image(systemName: "quote.closing")
                        .foregroundColor(Color.secondary)
                }
            
            if let hlAuthorPubkey = highlightAttributes.authorPubkey {
                HStack {
                    Spacer()
                    PFP(pubkey: hlAuthorPubkey, nrContact: highlightAttributes.contact, size: 20)
                    Text(highlightAttributes.anyName ?? "Unknown")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateTo(ContactPath(key: hlAuthorPubkey), context: dim.id)
                }
                .padding(.trailing, 40)
            }
            HStack {
                Spacer()
                if let url = highlightAttributes.url, let md = try? AttributedString(markdown:"[\(url)](\(url))") {
                    Text(md)
                        .lineLimit(1)
                        .font(.caption)
                }
            }
            .padding(.trailing, 40)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
        )
    }
}


// TODO: handle "source":
//"tags": [
//  [
//    "e",
//    "bc3d47e7f9bba39c89d969d7c2e09ba74e5bb4cd517aa99542ccbbb4d323fcbe",
//    "source"
//  ]
//]
