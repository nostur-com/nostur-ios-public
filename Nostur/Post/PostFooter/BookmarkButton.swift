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
    private var theme:Theme
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    var body: some View {
        Image(systemName: footerAttributes.bookmarked ? "bookmark.fill" : "bookmark")
            .padding(.trailing, isLast ? 0 : 10)
            .padding(.leading, isFirst ? 0 : 10)
            .padding(.vertical, 5)
            .padding(.trailing, isLast ? 10: 0)
            .foregroundColor(footerAttributes.bookmarked ? .orange : theme.footerButtons)
            .contentShape(Rectangle())
            .padding(.trailing, isLast ? -10 : 0)
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        tap()
                    }
            )
    }
    
    private func tap() {
        if footerAttributes.bookmarked {
            Bookmark.removeBookmark(nrPost)
            bg().perform {
                accountCache()?.addBookmark(nrPost.id)
            }
        }
        else {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            Bookmark.addBookmark(nrPost)
            bg().perform {
                accountCache()?.removeBookmark(nrPost.id)
            }
        }
    }
}

