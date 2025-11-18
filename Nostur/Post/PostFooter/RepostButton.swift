//
//  RepostButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct RepostButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    private var isFirst: Bool
    private var isLast: Bool
    private var isItem: Bool
    private var theme: Theme
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, isItem: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.isItem = isItem // Only quote post, not repost
        self.theme = theme // Only quote post, not repost
    }
    
    var body: some View {
        Image(systemName: "arrow.2.squarepath")
            .foregroundColor(footerAttributes.reposted ? .green : theme.footerButtons)
            .overlay(alignment: .leading) {
                AnimatedNumber(number: footerAttributes.repostsCount)
                    .opacity(footerAttributes.repostsCount == 0 ? 0 : 1.0)
                    .frame(width: 28)
                    .offset(x: 20)
            }
            .padding(.trailing, 27)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if isItem {
                    sendNotification(.createNewQuotePost, QuotePost(nrPost: nrPost))
                }
                else {
                    sendNotification(.createNewQuoteOrRepost, QuoteOrRepost(nrPost: nrPost))
                }
            }
    }
}

struct VideoRepostButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    private var isFirst: Bool
    private var isLast: Bool
    private var isItem: Bool
    private var theme: Theme
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, isItem: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.isItem = isItem // Only quote post, not repost
        self.theme = theme // Only quote post, not repost
    }
    
    var body: some View {
        VStack {
            Image(systemName: "arrow.2.squarepath")
                .foregroundColor(footerAttributes.reposted ? .green : theme.footerButtons)
            AnimatedNumber(number: footerAttributes.repostsCount)
                .opacity(footerAttributes.repostsCount == 0 ? 0 : 1.0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isItem {
                sendNotification(.createNewQuotePost, QuotePost(nrPost: nrPost))
            }
            else {
                sendNotification(.createNewQuoteOrRepost, QuoteOrRepost(nrPost: nrPost))
            }
        }
    }
}
