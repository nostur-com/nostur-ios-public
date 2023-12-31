//
//  ReactionButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/10/2023.
//

import SwiftUI

struct ReactionButton: View, Equatable {
    static func == (lhs: ReactionButton, rhs: ReactionButton) -> Bool {
        true
    }
    private let nrPost:NRPost
    private let reactionContent:String
    private var isFirst:Bool
    private var isLast:Bool
    
    init(nrPost: NRPost, reactionContent:String = "+", isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.reactionContent = reactionContent
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    var body: some View {
        ReactionButtonInner(nrPost: nrPost, reactionContent: reactionContent, isFirst: isFirst, isLast: isLast)
    }
}

struct ReactionButtonInner: View {
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
    
    private var isActivated:Bool {
        footerAttributes.reactions.contains(reactionContent)
    }
    
    var body: some View {
        Text(reactionContent)
            .frame(width: 20)
            .opacity(isActivated ? 1.0 : 0.7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                tap()
            }
    }
    
    private func tap() {
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
