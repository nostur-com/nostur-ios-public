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
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    var body: some View {
        if (footerAttributes.liked) {
            HStack {
                Image("LikeIconActive")
                    .foregroundColor(.red)
                AnimatedNumber(number: footerAttributes.likesCount)
//                            .equatable()
                    .opacity(footerAttributes.likesCount == 0 ? 0 : 1)
            }
            .foregroundColor(.red)
            .padding(.vertical, 5)
            .padding(.leading, isFirst ? 0 : 5)
            .padding(.trailing, isLast ? 0 : 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
                    nrPost.unlike()
                    unpublishLikeId = nil
                }
            }
        }
        else {
            HStack {
                Image("LikeIcon")
                AnimatedNumber(number: footerAttributes.likesCount)
//                            .equatable()
                    .opacity(footerAttributes.likesCount == 0 ? 0 : 1)
            }
            .padding(.vertical, 5)
            .padding(.leading, isFirst ? 0 : 5)
            .padding(.trailing, isLast ? 0 : 5)
            .contentShape(Rectangle())
            .onTapGesture {
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
}
