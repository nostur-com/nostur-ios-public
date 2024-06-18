//
//  ReactionButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/10/2023.
//

import SwiftUI

struct ReactionButton: View, Equatable {
    static func == (lhs: ReactionButton, rhs: ReactionButton) -> Bool {
        lhs.nrPost.id == rhs.nrPost.id && lhs.reactionContent == rhs.reactionContent
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
    private let nrPost: NRPost
    private let reactionContent: String
    @State private var unpublishLikeId: UUID? = nil
    private var isFirst: Bool
    private var isLast: Bool
    
    init(nrPost: NRPost, reactionContent: String = "+", isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.reactionContent = reactionContent
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    @State private var isActivated = false
    
    var body: some View {
        Text(reactionContent)
            .frame(width: 20)
            .opacity(isActivated ? 1.0 : 0.7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                tap()
            }
            .onAppear {
                isActivated = reactionContent != "+" && (accountCache()?.hasReaction(nrPost.id, reactionType: reactionContent) ?? false)
            }
    }
    
    @MainActor
    private func tap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        if unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            nrPost.unlike(self.reactionContent)
            unpublishLikeId = nil
            isActivated = false
        }
        else {
            guard !isActivated else { return }
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            unpublishLikeId = UUID()
            
            guard var likeNEvent = nrPost.like(self.reactionContent, uuid: unpublishLikeId!) else { return }
            isActivated = true
            
            if account.isNC {
                likeNEvent.publicKey = account.publicKey
                likeNEvent = likeNEvent.withId()
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
                _ = Unpublisher.shared.publish(signedEvent, cancellationId: unpublishLikeId)
            }
        }
    }
}
