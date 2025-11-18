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
    @State private var selectedEmoji = ""
    @State private var alreadySelectedEmoji: String? = nil
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
        if let alreadySelectedEmoji {
            Text(alreadySelectedEmoji)
        }
        else if selectedEmoji != "" {
            Text(selectedEmoji)
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
                    if selectedEmoji != "" {
                        tap(reactionContent: selectedEmoji) // unreact
                    }
                    else {
                        tap() // unlike
                    }
                }
                .onLongPressGesture(minimumDuration: 0.1) {
                    guard selectedEmoji == "" else { return }
                    AppSheetsModel.shared.emojiRR = EmojiPickerFor(footerAttributes: footerAttributes, selectedEmoji: Binding(get: {
                        return selectedEmoji
                    }, set: { newValue in
                        self.selectedEmoji = newValue
                    }))
                }
                .onReceive(receiveNotification(.postAction), perform: { notification in
                    // For updating the like button in multiple views. Example: like in detail, should also update if the event is visible somewhere else in feed.
                    let postAction = notification.object as! PostActionNotification
                    guard postAction.eventId == nrPost.id else { return }
                    
                    switch postAction.type {
                    case .reacted(let uuid, _):
                        if selectedEmoji == "" {
                            checkForAlreadyCustomEmojiReaction()
                        }
                        unpublishLikeId = uuid
                    case .unreacted(let reactionContent):
                        guard selectedEmoji != "" && reactionContent == selectedEmoji else { return }
                        footerAttributes.ourReactions.remove(selectedEmoji)
                        unpublishLikeId = nil
                    default:
                        break
                    }
                })
                .onChange(of: selectedEmoji) { newValue in
                    guard newValue != "" else { return }
                    guard alreadySelectedEmoji == nil else { return }
                    AppSheetsModel.shared.emojiRR = nil
                    tap(reactionContent: newValue)
                }
                .onAppear {
                    checkForAlreadyCustomEmojiReaction()
                }
    }
    
    private func tap(reactionContent: String = "+") {
        // UNREACT
        if (footerAttributes.ourReactions.contains("+") || selectedEmoji != "") && unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            nrPost.unlike(reactionContent)
            unpublishLikeId = nil
            bg().perform {
                accountCache()?.removeReaction(nrPost.id, reactionType: reactionContent)
            }
            selectedEmoji = ""
        }
        else { // REACT
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
    
    private func checkForAlreadyCustomEmojiReaction() {
        if let accountCache = accountCache() {
            let ourReactions = accountCache.getOurReactions(nrPost.id)
            if let customEmojiNotInOtherButtons = ourReactions.subtracting(ViewModelCache.shared.buttonIds).first {
                alreadySelectedEmoji = customEmojiNotInOtherButtons
            }
        }
    }
}


struct VideoEmojiButton: View {
    private let nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    @State private var selectedEmoji = ""
    @State private var alreadySelectedEmoji: String? = nil
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
        if let alreadySelectedEmoji {
            Text(alreadySelectedEmoji)
        }
        else if selectedEmoji != "" {
            Text(selectedEmoji)
        }
        else {
            Image(systemName: "heart.fill")
                .foregroundColor(footerAttributes.ourReactions.contains("+")  ? .red : theme.footerButtons)
        }
    }
    
    var body: some View {
        VStack {
            emojiOrLikeButton
            AnimatedNumber(number: footerAttributes.likesCount)
                .opacity(footerAttributes.likesCount == 0 ? 0 : 1)
        }
            
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedEmoji != "" {
                tap(reactionContent: selectedEmoji) // unreact
            }
            else {
                tap() // unlike
            }
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            guard selectedEmoji == "" else { return }
            AppSheetsModel.shared.emojiRR = EmojiPickerFor(footerAttributes: footerAttributes, selectedEmoji: Binding(get: {
                return selectedEmoji
            }, set: { newValue in
                self.selectedEmoji = newValue
            }))
        }
        .onReceive(receiveNotification(.postAction), perform: { notification in
            // For updating the like button in multiple views. Example: like in detail, should also update if the event is visible somewhere else in feed.
            let postAction = notification.object as! PostActionNotification
            guard postAction.eventId == nrPost.id else { return }
            
            switch postAction.type {
            case .reacted(let uuid, _):
                if selectedEmoji == "" {
                    checkForAlreadyCustomEmojiReaction()
                }
                unpublishLikeId = uuid
            case .unreacted(let reactionContent):
                guard selectedEmoji != "" && reactionContent == selectedEmoji else { return }
                footerAttributes.ourReactions.remove(selectedEmoji)
                unpublishLikeId = nil
            default:
                break
            }
        })
        .onChange(of: selectedEmoji) { newValue in
            guard newValue != "" else { return }
            guard alreadySelectedEmoji == nil else { return }
            AppSheetsModel.shared.emojiRR = nil
            tap(reactionContent: newValue)
        }
        .onAppear {
            checkForAlreadyCustomEmojiReaction()
        }
    }
    
    private func tap(reactionContent: String = "+") {
        // UNREACT
        if (footerAttributes.ourReactions.contains("+") || selectedEmoji != "") && unpublishLikeId != nil && Unpublisher.shared.cancel(unpublishLikeId!) {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            nrPost.unlike(reactionContent)
            unpublishLikeId = nil
            bg().perform {
                accountCache()?.removeReaction(nrPost.id, reactionType: reactionContent)
            }
            selectedEmoji = ""
        }
        else { // REACT
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
    
    private func checkForAlreadyCustomEmojiReaction() {
        if let accountCache = accountCache() {
            let ourReactions = accountCache.getOurReactions(nrPost.id)
            if let customEmojiNotInOtherButtons = ourReactions.subtracting(ViewModelCache.shared.buttonIds).first {
                alreadySelectedEmoji = customEmojiNotInOtherButtons
            }
        }
    }
}

struct EmojiPickerFor {
    var id = UUID()
    var footerAttributes: FooterAttributes
    var selectedEmoji: Binding<String>
}
