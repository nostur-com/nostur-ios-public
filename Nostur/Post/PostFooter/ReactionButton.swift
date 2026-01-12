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
            .onReceive(receiveNotification(.postAction), perform: { notification in
                // For updating the like button in multiple views. Example: like in detail, should also update if the event is visible somewhere else in feed.
                let postAction = notification.object as! PostActionNotification
                guard postAction.eventId == nrPost.id else { return }
                
                switch postAction.type {
                case .reacted(let uuid, let reactionContent):
                    if !isActivated && reactionContent == self.reactionContent {
                        isActivated = true
                    }
                    unpublishLikeId = uuid
                case .unreacted(let reactionContent):
                    if isActivated && reactionContent == self.reactionContent {
                        isActivated = false
                        unpublishLikeId = nil
                    }
                default:
                    break
                }
            })
    }
    
    @MainActor
    private func tap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        if unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
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
            
            likeNEvent.publicKey = account.publicKey
            
            if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(likeNEvent.publicKey)) {
                likeNEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
            }
            
            if account.isNC {
                likeNEvent = likeNEvent.withId()
                RemoteSignerManager.shared.requestSignature(forEvent: likeNEvent, usingAccount: account, whenSigned: { signedEvent in
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

struct VideoReactionButton: View {
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
            .foregroundStyle(Color.white)
            .font(.system(size: 20))
            .lineLimit(1)
            .opacity(isActivated ? 1.0 : 0.7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                tap()
            }
            .onAppear {
                isActivated = reactionContent != "+" && (accountCache()?.hasReaction(nrPost.id, reactionType: reactionContent) ?? false)
            }
            .onReceive(receiveNotification(.postAction), perform: { notification in
                // For updating the like button in multiple views. Example: like in detail, should also update if the event is visible somewhere else in feed.
                let postAction = notification.object as! PostActionNotification
                guard postAction.eventId == nrPost.id else { return }
                
                switch postAction.type {
                case .reacted(let uuid, let reactionContent):
                    if !isActivated && reactionContent == self.reactionContent {
                        isActivated = true
                    }
                    unpublishLikeId = uuid
                case .unreacted(let reactionContent):
                    if isActivated && reactionContent == self.reactionContent {
                        isActivated = false
                        unpublishLikeId = nil
                    }
                default:
                    break
                }
            })
    }
    
    @MainActor
    private func tap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        if unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
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
            
            likeNEvent.publicKey = account.publicKey
            
            if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(likeNEvent.publicKey)) {
                likeNEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
            }
            
            if account.isNC {
                likeNEvent = likeNEvent.withId()
                RemoteSignerManager.shared.requestSignature(forEvent: likeNEvent, usingAccount: account, whenSigned: { signedEvent in
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
