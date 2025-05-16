//
//  LikeButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2025.
//

import SwiftUI

struct EmojiButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    @State private var unpublishLikeId: UUID? = nil
    private var isFirst: Bool
    private var isLast: Bool
    private var theme: Theme
    
    @State private var isPresented = false
    @State private var selectedEmoji = ""
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    var body: some View {
            ZStack {
                if selectedEmoji != "" {
                    Text(selectedEmoji)
                }
                else {
                    Image(systemName: footerAttributes.liked ? "heart.fill" : "heart")
                }
            }
            .foregroundColor(footerAttributes.liked ? .red : theme.footerButtons)
            .overlay(alignment: .leading) {
                AnimatedNumber(number: footerAttributes.likesCount)
                    .opacity(footerAttributes.likesCount == 0 ? 0 : 1)
                    .frame(width: 26)
                    .offset(x: 18)
            }
            .padding(.trailing, 30)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                tap()
            }
            .onLongPressGesture(minimumDuration: 0.1) {
                guard selectedEmoji == "" else { return }
                isPresented = true
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
            .emojiPicker(
                isPresented: $isPresented,
                selectedEmoji: $selectedEmoji
            )
            .onChange(of: selectedEmoji) { newValue in
                guard newValue != "" else { return }
                tap(reactionContent: newValue)
            }
    }
    
    private func tap(reactionContent: String = "+") {
        if (footerAttributes.liked || selectedEmoji != "") && unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            nrPost.unlike(selectedEmoji != "" ? selectedEmoji : "+")
            unpublishLikeId = nil
            selectedEmoji = ""
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
            
            guard var likeNEvent = nrPost.like(reactionContent, uuid: unpublishLikeId!) else { return }
            
            likeNEvent.publicKey = account.publicKey
            if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(likeNEvent.publicKey)) {
                likeNEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
            }
            
            if account.isNC {
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
