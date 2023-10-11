//
//  ReplyButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct ReplyButton: View {
    @EnvironmentObject private var theme:Theme
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    private var isDetail:Bool
    private var isFirst:Bool
    private var isLast:Bool
    
    init(nrPost: NRPost, isDetail: Bool = false, isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    var body: some View {
            Image(footerAttributes.replied ? "ReplyIconActive" : "ReplyIcon")
                .foregroundColor(footerAttributes.replied ? theme.accent : theme.footerButtons)
                .overlay(alignment: .topLeading) {
                    if !isDetail && !footerAttributes.replyPFPs.isEmpty {
                        ZStack(alignment:.leading) {
                            ForEach(footerAttributes.replyPFPs.indices, id:\.self) { index in
                                MiniPFP(pictureUrl: footerAttributes.replyPFPs[index])
                                    .id(index)
                                    .zIndex(-Double(index))
                                    .offset(x:Double(0 + (12*index)))
                            }
                        }
                        .offset(y: 20)
                    }
                }
                .overlay(alignment: .leading) {
                    AnimatedNumber(number: footerAttributes.repliesCount)
                        .opacity(footerAttributes.repliesCount == 0 ? 0 : 1.0)
                        .frame(width: 26)
                        .offset(x: 18)
//                    AnimatedNumber(number: 347)
//                        .frame(width: 26)
//                        .offset(x: 18)
                }
                .padding(.trailing, 30)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    sendNotification(.createNewReply, EventNotification(event: nrPost.event))
                }   
    }
}
