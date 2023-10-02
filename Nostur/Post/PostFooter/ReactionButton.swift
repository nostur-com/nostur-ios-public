//
//  ReactionButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/10/2023.
//

import SwiftUI

struct ReactionButton: View {
    @EnvironmentObject private var theme:Theme
    private let nrPost:NRPost
    private let reactionContent:String
    @ObservedObject private var footerAttributes:FooterAttributes
    @State private var unpublishLikeId:UUID? = nil
    private var isFirst:Bool
    private var isLast:Bool
    
    init(nrPost: NRPost, reactionContent:String = "+", isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.reactionContent = reactionContent
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    var body: some View {
        Text(reactionContent)
            .opacity(footerAttributes.reactions.contains(reactionContent) ? 1.0 : 0.5)
            .padding(5)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isFullAccount() else { showReadOnlyMessage(); return }
                guard let account = account() else { return }
                if unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
                    nrPost.unlike(self.reactionContent)
                    unpublishLikeId = nil
                }
                else {
                    guard !footerAttributes.reactions.contains(reactionContent) else { return }
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    
                    var likeNEvent = nrPost.like(self.reactionContent)
                    
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
