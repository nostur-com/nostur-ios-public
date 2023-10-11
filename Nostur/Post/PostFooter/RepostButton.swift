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
        Image(systemName: "arrow.2.squarepath")
            .foregroundColor(footerAttributes.reposted ? .green : theme.footerButtons)
            .overlay(alignment: .leading) {
                AnimatedNumber(number: footerAttributes.repostsCount)
                    .opacity(footerAttributes.repostsCount == 0 ? 0 : 1.0)
                    .frame(width: 28)
                    .offset(x: 20)
                //                    AnimatedNumber(number: 234)
                //                        .frame(width: 28)
                //                        .offset(x: 20)
            }
            .padding(.trailing, 30)
        //                .background(.red)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !footerAttributes.reposted else { return }
                sendNotification(.createNewQuoteOrRepost, nrPost.event.toMain())
            }
    }
}
