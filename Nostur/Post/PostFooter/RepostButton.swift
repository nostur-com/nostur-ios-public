//
//  RepostButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct RepostButton: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    @ObservedObject var footerAttributes:FooterAttributes
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
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
            .padding(5)
        }
        else {
            HStack {
                Image("RepostedIcon")
                AnimatedNumber(number: footerAttributes.repostsCount)
//                            .equatable()
                    .opacity(footerAttributes.repostsCount == 0 ? 0 : 1)
            }
            .padding(5)
            .contentShape(Rectangle())
            .onTapGesture {
                sendNotification(.createNewQuoteOrRepost, nrPost.event.toMain())
            }
        }
    }
}
