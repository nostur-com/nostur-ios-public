//
//  Box.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/08/2023.
//

import SwiftUI

struct Box<Content: View>: View {
    let content: Content
    let kind: Int64
    let navMode: NavigationMode
    var nrPost: NRPost? = nil
    
    public enum NavigationMode {
        // Normal onTapGesture on entire view, but this makes Video in UIViewRepresentable not tappable
        case view
        
        // Workaround: make entire background tappable
        // Then in the individual subviews handle navigation tap
        // Mostly needed for making the area below pfp on post tapable, cannot do that there without breaking other things. must be done on a wrapper view
        case background
    }
    
    init(nrPost:NRPost? = nil, navMode:NavigationMode? = .background, @ViewBuilder _ content:()->Content) {
        self.kind = nrPost?.kind ?? 1
        self.navMode = navMode ?? .background
        self.nrPost = nrPost
        self.content = content()
    }
    
    var body: some View {
        //        VStack(spacing: 10) {
        //            content
        //        }
        if navMode == .view {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background(kind == 30023 ? Color(.secondarySystemBackground) : Color.systemBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    navigate()
                }
        }
        else {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background {
                    if kind == 30023 {
                        Color(.secondarySystemBackground)
                            .onTapGesture {
                                navigate()
                            }
                    }
                    else {
                        Color.systemBackground
                            .onTapGesture {
                                navigate()
                            }
                    }
                }
        }
    }
    
    private func navigate() {
        guard let nrPost = nrPost else { return }
        if nrPost.isRepost {
            if let firstQuote = nrPost.firstQuote {
                navigateTo(firstQuote)
            }
            else if let firstQuoteId = nrPost.firstQuoteId {
                navigateTo(NotePath(id: firstQuoteId))
            }
        }
        else {
            navigateTo(nrPost)
        }
    }
}
