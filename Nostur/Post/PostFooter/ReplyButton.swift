//
//  ReplyButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct ReplyButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    private var isDetail: Bool
    private var isFirst :Bool
    private var isLast: Bool
    private var theme: Theme
    
    init(nrPost: NRPost, isDetail: Bool = false, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    var body: some View {
            Image(systemName: footerAttributes.replied ? "bubble.left.fill" : "bubble.left")
                .foregroundColor(footerAttributes.replied ? theme.accent : theme.footerButtons)
                .overlay(alignment: .topLeading) {
                    if !isDetail && !footerAttributes.replyPFPs.isEmpty { // TODO: Mabye this shouldn't be here but in PostLayout() or Kind1()
                        ZStack(alignment:.leading) {
                            ForEach(footerAttributes.replyPFPs.indices, id:\.self) { index in
                                MiniPFP(pictureUrl: footerAttributes.replyPFPs[index])
                                    .id(index)
                                    .zIndex(-Double(index))
                                    .offset(x:Double(0 + (12*index)))
                            }
                        }
                        .offset(y: 17)
                    }
                }
                .overlay(alignment: .leading) {
                    AnimatedNumber(number: footerAttributes.repliesCount)
                        .opacity(footerAttributes.repliesCount == 0 ? 0 : 1.0)
                        .frame(width: 26)
                        .offset(x: 18, y: -1)
//                    AnimatedNumber(number: 347)
//                        .frame(width: 26)
//                        .offset(x: 18)
                }
                .padding(.trailing, 30)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    tap()
                }
    }
    
    private func tap() {
        sendNotification(.createNewReply, ReplyTo(nrPost: nrPost))
    }
}

import NavigationBackport

struct VideoReplyButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    private var isDetail: Bool
    private var isFirst :Bool
    private var isLast: Bool
    private var theme: Theme
    
    @State private var commentsDetail: ReplyTo? = nil
    
    init(nrPost: NRPost, isDetail: Bool = false, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: footerAttributes.replied ? "bubble.left.fill" : "bubble.left")
                .foregroundColor(footerAttributes.replied ? theme.accent : Color.white)

               
            AnimatedNumber(number: footerAttributes.repliesCount)
                .foregroundStyle(Color.white)
                .font(.system(size: 20))
                .lineLimit(1)
                .opacity(footerAttributes.repliesCount == 0 ? 0 : 1.0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            tap()
        }
        .nbNavigationDestination(item: $commentsDetail) { replyTo in
            CommentsDetail(nrPost: replyTo.nrPost)
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func tap() {
        commentsDetail = ReplyTo(nrPost: nrPost)
//        AppSheetsModel.shared.showReplyToSheet = ReplyTo(nrPost: nrPost)
    }
}
