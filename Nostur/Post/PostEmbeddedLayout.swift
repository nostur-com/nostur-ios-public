//
//  PostEmbeddedView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

struct PostEmbeddedLayout<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
    private var forceAutoload: Bool
    private var fullWidth: Bool

    private let content: Content
    private let authorAtBottom: Bool
    
    init(nrPost: NRPost, fullWidth: Bool = false, forceAutoload: Bool = false, authorAtBottom: Bool = false, @ViewBuilder _ content: () -> Content) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.forceAutoload = forceAutoload
        self.fullWidth = fullWidth
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
                            PFP(pubkey: nrPost.pubkey, pictureUrl: nrContact.pictureUrl, size: 20, forceFlat: nxViewingContext.contains(.screenshot))
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
                                }
                            
                            Text(nrContact.anyName) // Name
                                .animation(.easeIn, value: nrContact.anyName)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fontWeightBold()
                                .lineLimit(1)
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
                                }
                                
                            
                            PossibleImposterLabelView(nrContact: nrContact)
                            
                            Group {
                                Text(verbatim: "·")
                                Ago(nrPost.createdAt)
                                    .equatable()
                                if let via = nrPost.via {
                                    Text("· via \(via)")
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }
                    ReplyingToFragmentView(nrPost: nrPost)
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
                    PFP(pubkey: nrPost.pubkey, pictureUrl: nrContact.pictureUrl, size: 20, forceFlat: nxViewingContext.contains(.screenshot))
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
                        }
                    
                    Text(nrContact.anyName) // Name
                        .animation(.easeIn, value: nrContact.anyName)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fontWeightBold()
                        .lineLimit(1)
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
                        }
                        
                    PossibleImposterLabelView(nrContact: nrContact)
                    
                    Group {
                        Text(verbatim: "·")
                        Ago(nrPost.createdAt)
                            .equatable()
                        if let via = nrPost.via {
                            Text("· via \(via)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
        .clipped()
    }
    
    private func navigateToPost() {
        guard !nxViewingContext.contains(.preview) else { return }
        navigateTo(nrPost, context: containerID)
    }
}
