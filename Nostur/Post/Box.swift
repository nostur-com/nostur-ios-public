//
//  Box.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/08/2023.
//

import SwiftUI

import SwiftUI

struct Box<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID

    private let content: Content
    private let kind: Int64
    private let navMode: NavigationMode
    private let nrPost: NRPost?
    private let showGutter: Bool

    private let padding: CGFloat

    public enum NavigationMode {
        case view, background, noNavigation
    }

    init(
        nrPost: NRPost? = nil,
        navMode: NavigationMode? = .background,
        showGutter: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.nrPost = nrPost
        self.kind = nrPost?.kind ?? 1
        self.showGutter = showGutter

        // Compute static values upfront to avoid body recomputation
        let isDeleted = nrPost?.postRowDeletableAttributes.deletedById != nil
        self.navMode = isDeleted ? .noNavigation : (navMode ?? .background)

        self.padding = (nrPost?.kind == 30023) ? 20 : 10
        self.content = content()
    }

    var body: some View {
        let backgroundColor = (nrPost?.kind == 30023 || ((nrPost?.kind ?? 0) == 6 && (nrPost?.firstQuote?.kind ?? 0) == 30023))
            ? theme.secondaryBackground
            : theme.listBackground
        
        content
            .padding(padding)
            .background {
                backgroundColor
                    .onTapGesture(perform: navigate)
            }            
            .overlay(alignment: .bottom) {
                if showGutter {
                    theme.background.frame(height: GUTTER)
                }
        }
    }

    private func navigate() {
        guard navMode != .noNavigation && !nxViewingContext.contains(.preview), let nrPost else { return }

        if nrPost.isRepost {
            if let quote = nrPost.firstQuote {
                navigateTo(quote, context: containerID)
            } else if let id = nrPost.firstQuoteId {
                navigateTo(NotePath(id: id), context: containerID)
            }
        } else if let liveEvent = nrPost.nrLiveEvent {
            navigateTo(liveEvent, context: containerID)
        } else {
            navigateTo(nrPost, context: containerID)
        }
    }
}
