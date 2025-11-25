//
//  ReplyToSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/11/2025.
//

import SwiftUI

struct CommentsDetail: View {
    @Environment(\.theme) private var theme
    @ObservedObject public var nrPost: NRPost
    @State private var didLoad = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: GUTTER) {
                ThreadReplies(nrPost: nrPost)
                    .environment(\.nxViewingContext, [.selectableText, .postReply, .detailPane])
                
                
                
                Button("Add comment") {
                    sendNotification(.createNewReply, ReplyTo(nrPost: nrPost))
                }
                .padding(.top, 20)
            }
        }
        .background(theme.listBackground)
        .environment(\.nxViewingContext, [.selectableText, .detailPane])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            
            // If we navigated to this post by opening it from an embedded
            nrPost.footerAttributes.loadFooter()
            
        }
    }
}

#Preview {
    CommentsDetail(nrPost: testNRPost())
}
