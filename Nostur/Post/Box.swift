//
//  Box.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/08/2023.
//

import SwiftUI

struct Box<Content: View>: View {    
    private let content: Content
    private let kind: Int64
    private let navMode: NavigationMode
    private var nrPost: NRPost? = nil
    private var theme: Theme
    
    public enum NavigationMode {
        // Normal onTapGesture on entire view, but this makes Video in UIViewRepresentable not tappable
        case view
        
        // Workaround: make entire background tappable
        // Then in the individual subviews handle navigation tap
        // Mostly needed for making the area below pfp on post tapable, cannot do that there without breaking other things. must be done on a wrapper view
        case background
        
        case noNavigation // no navigation
    }
    
    init(nrPost:NRPost? = nil, navMode:NavigationMode? = .background, theme:Theme = Themes.default.theme, @ViewBuilder content: () -> Content) {
        self.kind = nrPost?.kind ?? 1
        self.navMode = navMode ?? .background
        self.nrPost = nrPost
        self.content = content()
        self.theme = theme
    }
    
    var body: some View {
        //        VStack(spacing: 10) {
        //            content
        //        }
        if navMode == .view {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background(kind == 30023 ? theme.secondaryBackground : theme.background)
                .contentShape(Rectangle())
                .onTapGesture {
                    navigate()
                }
//                .withoutAnimation()
//                .transaction { transaction in
//                    transaction.animation = nil
//                }
        }
        else if navMode == .noNavigation {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background(kind == 30023 ? theme.secondaryBackground : theme.background)
                .contentShape(Rectangle())
                .onTapGesture {
                    
                }
//                .withoutAnimation()
//                .transaction { transaction in
//                    transaction.animation = nil
//                }
        }
        else {
            content
                .padding(kind == 30023 ? 20 : 10)
                .background {
                    if kind == 30023 || ((nrPost?.kind ?? 0) == 6) && (nrPost?.firstQuote?.kind ?? 0) == 30023 {
                        theme.secondaryBackground
//                            .withoutAnimation()
//                            .transaction { t in
//                                t.animation = nil
//                            }
                            .onTapGesture {
                                navigate()
                            }
                    }
                    else {
                        theme.background
//                            .withoutAnimation()
//                            .transaction { t in
//                                t.animation = nil
//                            }
                            .onTapGesture {
                                navigate()
                            }
                    }
                }
//                .transaction { t in
//                    t.animation = nil
//                }
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
