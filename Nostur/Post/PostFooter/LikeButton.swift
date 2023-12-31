//
//  LikeButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct LikeButton: View {
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    @State private var unpublishLikeId:UUID? = nil
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
        Image(systemName: footerAttributes.liked ? "heart.fill" : "heart")
            .foregroundColor(footerAttributes.liked ? .red : theme.footerButtons)
            .overlay(alignment: .leading) {
                AnimatedNumber(number: footerAttributes.likesCount)
                    .opacity(footerAttributes.likesCount == 0 ? 0 : 1)
                    .frame(width: 26)
                    .offset(x: 18)
                //                    AnimatedNumber(number: 547)
                //                        .frame(width: 26)
                //                        .offset(x: 18)
            }
            .padding(.trailing, 30)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        //                .background(.green)
            .onTapGesture {
                tap()
            }
    }
    
    private func tap() {
        if footerAttributes.liked && unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            nrPost.unlike()
            unpublishLikeId = nil
        }
        else {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            guard let account = account() else { return }
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            
            var likeNEvent = nrPost.like()
            
            if account.isNC {
                likeNEvent.publicKey = account.publicKey
                likeNEvent = likeNEvent.withId()
                unpublishLikeId = UUID()
                NSecBunkerManager.shared.requestSignature(forEvent: likeNEvent, usingAccount: account, whenSigned: { signedEvent in
                    if let unpublishLikeId = self.unpublishLikeId {
                        self.unpublishLikeId = Unpublisher.shared.publish(signedEvent, cancellationId: unpublishLikeId)
                    }
                })
            }
            else {
                guard let signedEvent = try? account.signEvent(likeNEvent) else {
                    L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                    return
                }
                unpublishLikeId = Unpublisher.shared.publish(signedEvent)
            }
        }
    }
}
