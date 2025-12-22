//
//  BalloonView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI
import NavigationBackport

struct BalloonView17: View {
    @ObservedObject public var nrChatMessage: NRChatMessage
    public var accountPubkey: String
    public var vm: ConversionVM
    
    private var isSentByCurrentUser: Bool {
        nrChatMessage.pubkey == accountPubkey
    }
    
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    @State private var showDMSendResult: RecipientResult? = nil
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        HStack {
            if isSentByCurrentUser {
                Spacer()
            }
            else if vm.receivers.count > 1 {
                ObservedPFP(nrContact: nrChatMessage.nrContact, size: 20)
                    .offset(x: 5, y: 5)
            }
            VStack(spacing: 3) {
                
                if let replyTo = nrChatMessage.replyTo {
                    EmbeddedChatMessage(nrChatMessage: replyTo, isSentByCurrentUser: isSentByCurrentUser)
                        .clipShape(.rect(cornerRadius: 14))
                        .onTapGesture {
                            vm.scrollToId = replyTo.id
                        }
                        .padding(.trailing, 15)
                }
                 
                DMContentRenderer(pubkey: nrChatMessage.pubkey, contentElements: nrChatMessage.contentElementsDetail, availableWidth: availableWidth, isSentByCurrentUser: isSentByCurrentUser)
                    .padding(.trailing, 16) // space for menu button
                
                if let quotedEvent = nrChatMessage.quotedEvent {
                    EmbeddedChatMessage(nrChatMessage: quotedEvent, isSentByCurrentUser: isSentByCurrentUser)
                        .clipShape(.rect(cornerRadius: 14))
                        .onTapGesture {
                            vm.scrollToId = quotedEvent.id
                        }
                }
            }
            .padding(10)
            .overlay(alignment: .topTrailing) {
                if vm.conversionVersion == 17 {
                    Menu {
                        Button("Reply...", systemImage: "arrowshape.turn.up.left") {
                            withAnimation {
                                vm.replyingNow = nrChatMessage
                            }
                        }
                        Button("Quote...", systemImage: "quote.bubble.rtl") {
                            withAnimation {
                                vm.quotingNow = nrChatMessage
                            }
                        }
    //                    Button("React...", systemImage: "smiley") { }
                    } label: {
                        Image(systemName: "ellipsis")
                            .padding(5)
                            .contentShape(Rectangle())
                            .foregroundStyle(isSentByCurrentUser ? Color.white : theme.accent)
                    }
                    .offset(x: -7, y: 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSentByCurrentUser ? theme.accent : theme.background)
            )
            .background(alignment: isSentByCurrentUser ? .bottomTrailing : .bottomLeading) {
                Image(systemName: "moon.fill")
                    .foregroundColor(isSentByCurrentUser ? theme.accent : theme.background)
                    .scaleEffect(x: isSentByCurrentUser ? 1 : -1)
                    .rotationEffect(.degrees(isSentByCurrentUser ? 35 : -35))
                    .offset(x: isSentByCurrentUser ? 10 : -10, y: 0)
                    .font(.system(size: 25))
            }
            .padding(.horizontal, 10)
            .padding(isSentByCurrentUser ? .leading : .trailing, 50)
            .overlay(alignment: isSentByCurrentUser ? .bottomLeading : .bottomTrailing) {
                Text(nrChatMessage.createdAt, format: .dateTime.hour().minute())
                    .frame(alignment: isSentByCurrentUser ? .leading : .trailing)
                    .font(.footnote)
                    .foregroundColor(nrChatMessage.nEvent.kind == .legacyDirectMessage ? .secondary : .primary)
                    .padding(.bottom, 8)
                    .padding(isSentByCurrentUser ? .leading : .trailing, 5)
            }
            
            if !isSentByCurrentUser {
                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 2) {
               
                Spacer()
                
                ForEach(Array(nrChatMessage.dmSendResult.keys).sorted(), id: \.self) { pubkey in
                    RecipientResultView(result: nrChatMessage.dmSendResult[pubkey]!)
                        .onTapGesture {
                            showDMSendResult = nrChatMessage.dmSendResult[pubkey]!
                        }
                }
            }
            .frame(height: 12)
            .padding(.trailing, 25)
            .padding(.bottom, 2)
        }
        .sheet(item: $showDMSendResult) { dmSendResult in
            NBNavigationStack {
                DMSendResultDetail(
                    dmSentResult: dmSendResult,
                    isOwnRelays: accountPubkey == dmSendResult.recipientPubkey
                )
            }
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    
    @Previewable @StateObject var vm = ConversionVM(
        participants: ["9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                       "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"],
        ourAccountPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"
    )

    let nrChatMessage = NRChatMessage(
        nEvent: NEvent(
            id: "173f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879",
            publicKey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
            createdAt: NTimestamp.init(date: Date()),
            content: "Hello there!",
            kind: .directMessage,
            tags: [],
            signature: ""
        )
    )
    
    let nrChatMessage2 = NRChatMessage(
        nEvent: NEvent(
            id: "273f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879",
            publicKey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
            createdAt: NTimestamp.init(date: Date()),
            content: "I will be quoted",
            kind: .directMessage,
            tags: [],
            signature: ""
        )
    )
    
    
    var nrChatMessage3 = NRChatMessage(
        nEvent: NEvent(
            id: "373f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879",
            publicKey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
            createdAt: NTimestamp.init(date: Date()),
            content: "I'm quoting someone",
            kind: .directMessage,
            tags: [ NostrTag(["q", "273f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879"]) ],
            signature: ""
        )
    )
    
    let _ = nrChatMessage3.quotedEvent = NRChatMessage(nEvent: nrChatMessage2.nEvent)
    
    var nrChatMessage4 = NRChatMessage(
        nEvent: NEvent(
            id: "373f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879",
            publicKey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
            createdAt: NTimestamp.init(date: Date()),
            content: "I'm replying to you",
            kind: .directMessage,
            tags: [ NostrTag(["e", "173f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879"]) ],
            signature: ""
        )
    )
    
    let _ = nrChatMessage4.replyTo = NRChatMessage(nEvent: nrChatMessage.nEvent)
    
    
    VStack {
        BalloonView17(nrChatMessage: nrChatMessage, accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", vm: vm)
        
        BalloonView17(nrChatMessage: nrChatMessage2, accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", vm: vm)
        
        BalloonView17(nrChatMessage: nrChatMessage3, accountPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33", vm: vm)
        
        BalloonView17(nrChatMessage: nrChatMessage4, accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", vm: vm)
        
        Spacer()
    }
}


struct ChatEmojiButton: View {
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
