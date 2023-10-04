//
//  BookmarkButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct BookmarkButton: View {
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    private var isFirst:Bool
    private var isLast:Bool
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    var body: some View {
        if (footerAttributes.bookmarked) {
            Image("BookmarkIconActive")
                .foregroundColor(.orange)
                .padding(.vertical, 5)
                .padding(.leading, isFirst ? 0 : 5)
                .padding(.trailing, isLast ? 0 : 5)
                .overlay {
                    Color.clear
                        .frame(width: 30)
                        .offset(x: -10)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                                    TapGesture()
                                        .onEnded { _ in
                                            NRState.shared.loggedInAccount?.removeBookmark(nrPost)
                                        }
                                )
                }
        }
        else {
            Image("BookmarkIcon")
                .padding(.vertical, 5)
                .padding(.leading, isFirst ? 0 : 5)
                .padding(.trailing, isLast ? 0 : 5)
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
                                            NRState.shared.loggedInAccount?.addBookmark(nrPost)
                                        }
                                )
                }
        }
    }
}
