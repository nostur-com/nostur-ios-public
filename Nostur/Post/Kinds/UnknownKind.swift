//
//  UnknownKind.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct UnknownKind: View {
    private var theme: Theme
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
    private let grouped: Bool
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false, theme: Theme) {
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
        self.grouped = grouped
        self.theme = theme
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
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost))
    }
    
    @StateObject private var model = UnknownKindModel()
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: true, theme: theme) {
            unknownKindView
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, theme: theme) {
            unknownKindView
        }
    }
    
    @ViewBuilder
    private var unknownKindView: some View {
        switch model.state {
        case .loading:
            CenteredProgressView()
                .frame(height: 150)
                .onAppear {
                    model.load(unknownKind: nrPost.kind, eventId: nrPost.id, pubkey: nrPost.pubkey, dTag: nrPost.dTag, alt: nrPost.alt)
                }
        case .ready((let suggestedApps, let title)):
            VStack(alignment: .leading) {
                HStack {
                    Text("\(Image(systemName: "app.fill")) \(title)")
                        .fontWeight(.bold).lineLimit(1)
                    Spacer()
//                    Button(action: showNip89Info, label: {
//                        Image(systemName: "questionmark.circle")
//                            .foregroundColor(theme.secondary)
//                            .font(.caption)
//                    })
                }
                if !suggestedApps.isEmpty {
                    Text("Open with").font(.caption).foregroundColor(theme.secondary)
                    Divider()
                        .padding(.horizontal, -10)
                    
                    ForEach(suggestedApps) { app in
                        AppRow(app: app,
                               theme: theme
                        )
                    }
                }
                else {
                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) kind \(Double(nrPost.kind).clean) type not (yet) supported")
                        .fontWeight(.bold).lineLimit(1)
                    NRTextDynamic((nrPost.content ?? nrPost.alt) ?? "")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        case .timeout:
            VStack {
                Label(String(localized: "kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a 'kind X' post is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                    .hCentered()
                    .frame(maxWidth: .infinity)
                    .background(theme.lineColor.opacity(0.2))
                NRTextDynamic((nrPost.content ?? nrPost.alt) ?? "")
            }
        }
    }
}
