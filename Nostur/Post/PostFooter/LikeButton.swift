//
//  LikeButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct LikeButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    @State private var unpublishLikeId: UUID? = nil
    private var isFirst: Bool
    private var isLast: Bool
    private var theme: Theme
    
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
//                AnimatedNumber(number: 547)
//                    .frame(width: 26)
//                    .offset(x: 18)
            }
            .padding(.trailing, 30)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                tap()
            }
            .onReceive(receiveNotification(.postAction), perform: { notification in
                // For updating the like button in multiple views. Example: like in detail, should also update if the event is visible somewhere else in feed.
                let postAction = notification.object as! PostActionNotification
                guard postAction.eventId == nrPost.id else { return }
                
                switch postAction.type {
                case .liked(let uuid):
                    footerAttributes.liked = true
                    unpublishLikeId = uuid
                case .unliked:
                    footerAttributes.liked = false
                    unpublishLikeId = nil
                default:
                    break
                }
            })
    }
    
    private func tap() {
        if footerAttributes.liked && unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            nrPost.unlike()
            unpublishLikeId = nil
            bg().perform {
                accountCache()?.removeLike(nrPost.id)
            }
        }
        else {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            guard let account = account() else { return }
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            unpublishLikeId = UUID()
            
            guard var likeNEvent = nrPost.like(uuid: unpublishLikeId!) else { return }
            bg().perform {
                accountCache()?.addLike(nrPost.id)
            }
            
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
