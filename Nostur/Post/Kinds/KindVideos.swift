//
//  KindVideos.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/11/2025.
//

import SwiftUI

struct KindVideos: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.availableHeight) private var availableHeight
    
    @ObservedObject private var settings: SettingsStore = .shared
    private let url: URL
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    
    private let hideFooter: Bool // For rendering in NewReply
    
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let forceAutoload: Bool

    init(url: URL, nrPost: NRPost, hideFooter: Bool = true, isDetail: Bool = false, isEmbedded: Bool = false, forceAutoload: Bool = false) {
        self.url = url
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.hideFooter = hideFooter
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
        Color.red
            .frame(height: availableHeight)
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            rowContent
        }
    }
    
    @ViewBuilder
    private var rowContent: some View {
        VStack {
            VideoEventView2(pubkey: nrPost.pubkey, title: nrPost.eventTitle ?? "Untitled", url: url, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, isNSFW: nrPost.isNSFW)
            
            ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: true, fullWidth: settings.fullWidthImages)
                .environment(\.availableWidth, availableWidth - 20)
                .padding(.top, 10)
        }
    }
    
    
    @ViewBuilder // When there are multiple images, put the text at the top
    private var detailContent: some View {
        VStack {
            VideoEventView2(pubkey: nrPost.pubkey, title: nrPost.eventTitle ?? "Untitled", url: url, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, isNSFW: nrPost.isNSFW)
            
            ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: true, fullWidth: settings.fullWidthImages)
                .environment(\.availableWidth, availableWidth - 20)
                .padding(.vertical, 10)
        }
    }
}
