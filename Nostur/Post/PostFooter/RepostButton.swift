//
//  RepostButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct RepostButton: View {
    @EnvironmentObject private var theme:Theme
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
        if (footerAttributes.reposted) {
            HStack {
                Image("RepostedIcon")
                    .foregroundColor(.green)
                AnimatedNumber(number: footerAttributes.repostsCount)
//                            .equatable()
                    .opacity(footerAttributes.repostsCount == 0 ? 0 : 1)
            }
            .foregroundColor(.green)
            .padding(.vertical, 5)
            .padding(.leading, isFirst ? 0 : 5)
            .padding(.trailing, isLast ? 0 : 5)
        }
        else {
            HStack {
                Image("RepostedIcon")
                AnimatedNumber(number: footerAttributes.repostsCount)
//                            .equatable()
                    .opacity(footerAttributes.repostsCount == 0 ? 0 : 1)
            }
            .padding(.vertical, 5)
            .padding(.leading, isFirst ? 0 : 5)
            .padding(.trailing, isLast ? 0 : 5)
            .contentShape(Rectangle())
            .onTapGesture {
                sendNotification(.createNewQuoteOrRepost, nrPost.event.toMain())
            }
        }
    }
}
