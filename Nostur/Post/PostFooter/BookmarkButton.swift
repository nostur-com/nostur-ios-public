//
//  BookmarkButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct BookmarkButton: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    @ObservedObject var footerAttributes:FooterAttributes
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
    }
    
    var body: some View {
        if (footerAttributes.bookmarked) {
            Image("BookmarkIconActive")
                .foregroundColor(.orange)
                .padding([.top,.leading,.bottom], 5)
                .overlay {
                    Color.clear
                        .frame(width: 30)
                        .offset(x: -10)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                                    TapGesture()
                                        .onEnded { _ in
                                            NosturState.shared.removeBookmark(nrPost)
                                        }
                                )
                }
        }
        else {
            Image("BookmarkIcon")
                .padding([.top,.leading,.bottom], 5)
                .overlay {
                    Color.clear
                        .frame(width: 30)
                        .offset(x: -10)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                                    TapGesture()
                                        .onEnded { _ in
                                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                            impactMed.impactOccurred()
                                            NosturState.shared.addBookmark(nrPost)
                                        }
                                )
                }
        }
    }
}
