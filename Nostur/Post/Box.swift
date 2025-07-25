//
//  Box.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/08/2023.
//

import SwiftUI

struct Box<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @EnvironmentObject private var dim: DIMENSIONS
    private let content: Content
    private let kind: Int64
    private let navMode: NavigationMode
    private var nrPost: NRPost? = nil
    private var showGutter: Bool
    
    public enum NavigationMode {
        // Normal onTapGesture on entire view, but this makes Video in UIViewRepresentable not tappable
        case view
        
        // Workaround: make entire background tappable
        // Then in the individual subviews handle navigation tap
        // Mostly needed for making the area below pfp on post tapable, cannot do that there without breaking other things. must be done on a wrapper view
        case background
        
        case noNavigation // no navigation
    }
    
    init(nrPost: NRPost? = nil, navMode: NavigationMode? = .background, showGutter: Bool = true, @ViewBuilder content: () -> Content) {
        self.kind = nrPost?.kind ?? 1
        
        // if not deleted: use given navMode or fallback to .background
        self.navMode = if nrPost?.postRowDeletableAttributes.deletedById == nil {
            (navMode ?? .background)
        }
        else { // if deleted, no navigation
            .noNavigation
        }
        
        self.nrPost = nrPost
        self.content = content()
        self.showGutter = showGutter
    }
    
    var body: some View {
        if navMode == .view {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background(kind == 30023 ? theme.secondaryBackground : theme.listBackground)
                .overlay(alignment: .bottom) {
                    if showGutter {
                        theme.background.frame(height: GUTTER)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigate()
                }
        }
        else if navMode == .noNavigation {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background(kind == 30023 ? theme.secondaryBackground : theme.listBackground)
                .overlay(alignment: .bottom) {
                    if showGutter {
                        theme.background.frame(height: GUTTER)
                    }
                }
        }
        else {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background {
                    if kind == 30023 || ((nrPost?.kind ?? 0) == 6) && (nrPost?.firstQuote?.kind ?? 0) == 30023 {
                        theme.secondaryBackground
                            .onTapGesture {
                                navigate()
                            }
                    }
                    else {
                        theme.listBackground
                            .onTapGesture {
                                navigate()
                            }
                    }
                }
                .overlay(alignment: .bottom) {
                    if showGutter {
                        theme.background.frame(height: GUTTER)
                    }
                }
        }
    }
    
    private func navigate() {
        guard !nxViewingContext.contains(.preview) else { return }
        guard let nrPost = nrPost else { return }
        if nrPost.isRepost {
            if let firstQuote = nrPost.firstQuote {
                navigateTo(firstQuote, context: dim.id)
            }
            else if let firstQuoteId = nrPost.firstQuoteId {
                navigateTo(NotePath(id: firstQuoteId), context: dim.id)
            }
        }
        else {
            if let liveEvent = nrPost.nrLiveEvent {
                navigateTo(liveEvent, context: dim.id)
            }
            else {
                navigateTo(nrPost, context: dim.id)
            }
        }
    }
}
