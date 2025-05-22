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
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    @ViewBuilder
    var emojiOrLikeButton: some View {
        if footerAttributes.selectedEmoji != "" {
            Text(footerAttributes.selectedEmoji)
        }
        else {
            Image(systemName: footerAttributes.ourReactions.contains("+") ? "heart.fill" : "heart")
                .foregroundColor(footerAttributes.ourReactions.contains("+")  ? .red : theme.footerButtons)
        }
    }
    
    var body: some View {
            emojiOrLikeButton
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
                    guard footerAttributes.selectedEmoji == "" else { return }
                    AppSheetsModel.shared.emojiRR = EmojiPickerFor(footerAttributes: footerAttributes)
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
                .onChange(of: footerAttributes.selectedEmoji) { newValue in
                    guard newValue != "" else { return }
                    AppSheetsModel.shared.emojiRR = nil
                    tap(reactionContent: newValue)
                }
    }
    
    private func tap(reactionContent: String = "+") {
        if (footerAttributes.liked || footerAttributes.selectedEmoji != "") && unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            nrPost.unlike(footerAttributes.selectedEmoji != "" ? footerAttributes.selectedEmoji : "+")
            unpublishLikeId = nil
            footerAttributes.selectedEmoji = ""
            bg().perform {
                accountCache()?.removeReaction(nrPost.id, reactionType: reactionContent)
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

struct EmojiPickerFor {
    var id = UUID()
    var footerAttributes: FooterAttributes
}
