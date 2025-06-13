//
//  PostEmbeddedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

struct PostEmbeddedLayout<Content: View>: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
    private var forceAutoload: Bool
    private var fullWidth: Bool
    private var theme: Theme
    @EnvironmentObject private var parentDIM: DIMENSIONS

    private let content: Content
    private let authorAtBottom: Bool
    
    init(nrPost: NRPost, fullWidth: Bool = false, forceAutoload: Bool = false, theme: Theme, authorAtBottom: Bool = false, @ViewBuilder _ content: () -> Content) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.forceAutoload = forceAutoload
        self.fullWidth = fullWidth
        self.theme = theme
        self.authorAtBottom = authorAtBottom
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) { // name + reply + context menu
                VStack(alignment: .leading) { // Name + menu "replying to"
                    if !authorAtBottom {
                        HStack(spacing: 5) {
                            // profile image
                            PFP(pubkey: nrPost.pubkey, pictureUrl: pfpAttributes.pfpURL, size: 20, forceFlat: nxViewingContext.contains(.screenshot))
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost, pfpAttributes: pfpAttributes, context: parentDIM.id)
                                }
                            
                            Text(pfpAttributes.anyName) // Name
                                .animation(.easeIn, value: pfpAttributes.anyName)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fontWeightBold()
                                .lineLimit(1)
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost, pfpAttributes: pfpAttributes, context: parentDIM.id)
                                }
                                
                            
                            PossibleImposterLabelView(pfp: nrPost.pfpAttributes)
                            
                            Group {
                                Text(verbatim: " ·") //
                                Ago(nrPost.createdAt)
                                    .equatable()
                                if let via = nrPost.via {
                                    Text(" · via \(via)") //
                                        .lineLimit(1)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.body)
                            .foregroundColor(.secondary)
                        }
                    }
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                }
                
                Spacer()
            }
            VStack(alignment: .leading) {
                content
            }
            if authorAtBottom {
                HStack(spacing: 5) {
                    Spacer()
                    // profile image
                    PFP(pubkey: nrPost.pubkey, pictureUrl: pfpAttributes.pfpURL, size: 20, forceFlat: nxViewingContext.contains(.screenshot))
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost, pfpAttributes: pfpAttributes, context: parentDIM.id)
                        }
                    
                    Text(pfpAttributes.anyName) // Name
                        .animation(.easeIn, value: pfpAttributes.anyName)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fontWeightBold()
                        .lineLimit(1)
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost, pfpAttributes: pfpAttributes, context: parentDIM.id)
                        }
                        
                    PossibleImposterLabelView(pfp: nrPost.pfpAttributes)
                    
                    Group {
                        Text(verbatim: " ·") //
                        Ago(nrPost.createdAt)
                            .equatable()
                        if let via = nrPost.via {
                            Text(" · via \(via)") //
                                .lineLimit(1)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .background(
            theme.listBackground
                .cornerRadius(8)
                .onTapGesture(perform: navigateToPost)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.lineColor, lineWidth: 1)
        )
    }
    
    private func navigateToPost() {
        guard !nxViewingContext.contains(.preview) else { return }
        navigateTo(nrPost, context: parentDIM.id)
    }
}
