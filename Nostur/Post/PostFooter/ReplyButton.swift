//
//  ReplyButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct ReplyButton: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    @ObservedObject var footerAttributes:FooterAttributes
    var isDetail = false
    
    init(nrPost: NRPost, isDetail: Bool = false) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.footerAttributes = nrPost.footerAttributes
    }
    
    var body: some View {
        HStack {
            Image(footerAttributes.replied ? "ReplyIconActive" : "ReplyIcon")
                .foregroundColor(footerAttributes.replied ? theme.accent : theme.footerButtons)
            AnimatedNumber(number: footerAttributes.repliesCount)
//                        .equatable()
                .opacity(footerAttributes.repliesCount == 0 ? 0 : 1)
            if !isDetail && !footerAttributes.replyPFPs.isEmpty {
                ZStack(alignment:.leading) {
                    ForEach(footerAttributes.replyPFPs.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: footerAttributes.replyPFPs[index])
                            .id(index)
                            .zIndex(-Double(index))
                            .offset(x:Double(0 + (15*index)))
                    }
                }
            }
        }
        .padding([.vertical, .trailing], 5)
        .contentShape(Rectangle())
        .onTapGesture {
            sendNotification(.createNewReply, EventNotification(event: nrPost.event))
        }
    }
}
