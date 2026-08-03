//
//  ChatRoom.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/07/2024.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct ChatRoom: View {
    @Environment(\.theme) private var theme
    public let aTag: String
    public let anonymous: Bool
    @ObservedObject public var chatVM: ChatRoomViewModel
    @ObservedObject private var settings: SettingsStore = .shared
    public var zoomableId: String = "Default"
    @Binding var selectedContact: NRContact?

    @State private var message: String = ""
    @State private var account: CloudAccount? = nil
    @State private var timer: Timer?
    @State private var attributedMessage = NSAttributedString()
    @State private var mentionSearchResults: [NRContact] = []
    @State private var mentionSearchCancellationToken: SearchCancellationToken?
    @State private var highlightedMessageId: String?
    @State private var replyingTo: NRChatMessage?
    @State private var quoting: NRChatMessage?
    @State private var composerFocusRequest = 0
    
    @Namespace private var bottom
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ScrollViewReader { proxy in
            if let account {
                VStack(spacing: 0) {
                    List {
                        switch chatVM.state {
                            case .initializing:
                                CenteredProgressView()
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .loading:
                                CenteredProgressView()
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .ready:
                                if chatVM.messages.isEmpty {
                                    VStack {
                                        Spacer()
                                        Text("Welcome to the chat")
                                        Spacer()
                                    }
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                                    .centered()
                                    .listRowInsets(.init())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                }
                                else {
                                    ForEach(chatVM.messages) { rowContent in
                                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                                            ChatRow(
                                                content: rowContent,
                                                displayUserAgent: settings.displayUserAgentEnabled,
                                                zoomableId: zoomableId,
                                                selectedContact: $selectedContact,
                                                onReplyPreviewTap: { parentId in
                                                    jumpToMessage(parentId, proxy: proxy)
                                                }
                                            )
                                            .equatable()
                                        }
                                        .padding(.vertical, 5)
                                        .background {
                                            if highlightedMessageId == rowContent.id {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(theme.accent.opacity(0.18))
                                            }
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if chatVM.pinnedMessageIds.contains(rowContent.id) {
                                                Image(systemName: "pin.fill")
                                                    .font(.caption)
                                                    .foregroundColor(theme.accent)
                                                    .accessibilityLabel("Pinned message")
                                            }
                                        }
                                        .scaleEffect(x: 1, y: -1, anchor: .center)
                                        .id(rowContent.id)
                                        .contextMenu {
                                            if case .chatMessage(let chatMessage) = rowContent {
                                                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                                                    withAnimation {
                                                        quoting = nil
                                                        replyingTo = chatMessage
                                                        composerFocusRequest += 1
                                                    }
                                                }

                                                Button("Quote", systemImage: "quote.bubble") {
                                                    withAnimation {
                                                        replyingTo = nil
                                                        quoting = chatMessage
                                                        composerFocusRequest += 1
                                                    }
                                                }

                                                if chatVM.canManagePins(account: account) {
                                                    let isPinned = chatVM.pinnedMessageIds.contains(rowContent.id)
                                                    Divider()
                                                    Button {
                                                        chatVM.togglePin(messageId: rowContent.id, account: account)
                                                    } label: {
                                                        Label(
                                                            isPinned ? "Unpin message" : "Pin message",
                                                            systemImage: isPinned ? "pin.slash" : "pin"
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .listRowInsets(.init())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))

                                    if chatVM.hasOlderMessages {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .scaleEffect(x: 1, y: -1, anchor: .center)
                                            .listRowInsets(.init())
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(.init(Color.clear))
                                            .onAppear {
                                                chatVM.loadOlderMessages()
                                            }
                                    }
                                }
                            case .timeout:
                                VStack {
                                    Text("timeout")
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(.init(Color.clear))
                                .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .error(let string):
                                Text(string)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                        }
                    }
                    .scrollContentBackgroundHidden()
                    .listStyle(.plain)
                    .safeAreaScroll()
                    .scaleEffect(x: 1, y: -1, anchor: .center)
                    .padding(.top, 20)
                    .overlay(alignment: .top) {
                        VStack(alignment: .trailing, spacing: 4) {
                            if !chatVM.pinnedMessages.isEmpty {
                                PinnedChatMessages(
                                    messages: chatVM.pinnedMessages,
                                    canManage: chatVM.canManagePins(account: account),
                                    onTap: { jumpToMessage($0, proxy: proxy) },
                                    onUnpin: { chatVM.togglePin(messageId: $0, account: account) }
                                )
                            }

                            if !chatVM.topZaps.isEmpty {
                                ChatTopZaps(messages: chatVM.topZaps)
                            }
                        }
                        .padding(.top, 45)
                        .padding(.horizontal, 5)
                    }
                    .onChange(of: chatVM.state) { newValue in
                        if newValue == .ready {
                            proxy.scrollTo(bottom)
                        }
                    }
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                    }
                    .onAppear {
                        try? chatVM.start(aTag: aTag)
                    }
                    
                    if !anonymous {
                        VStack(spacing: 0) {
                            if let mentionTerm = mentionQueryTerm(
                                in: message,
                                cursorUTF16Location: (message as NSString).length,
                                attributedText: attributedMessage
                            ) {
                                ChatMentionChoices(
                                    contacts: mentionChoices(for: mentionTerm, account: account),
                                    onSelect: { contact in
                                        selectMention(contact, term: mentionTerm)
                                    }
                                )
                                .task(id: mentionTerm) {
                                    await refreshMentionChoices(
                                        for: mentionTerm,
                                        account: account
                                    )
                                }
                            }

                            HStack {
                                MiniPFP(pictureUrl: account.pictureUrl, size: 40.0)
                                ChatInputField(
                                    message: $message,
                                    attributedMessage: $attributedMessage,
                                    startWithFocus: false,
                                    highlightMentions: true,
                                    replyingTo: replyingTo,
                                    quoting: quoting,
                                    focusRequest: composerFocusRequest,
                                    onRemoveReference: clearComposerReference,
                                    onSubmit: submitMessage
                                )
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            account = Nostur.account()
            startTimer()
            // Ensure resume if List onAppear already ran, or VM was paused
            try? chatVM.start(aTag: aTag)
        }
        .onDisappear {
            stopTimer()
            chatVM.pause()
        }
    }

    @MainActor
    private func jumpToMessage(_ id: String, proxy: ScrollViewProxy) {
        guard chatVM.revealMessage(id: id) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
            highlightedMessageId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    if highlightedMessageId == id {
                        highlightedMessageId = nil
                    }
                }
            }
        }
    }
    
    private func submitMessage() {
        // Create and send chat message (via unpublisher?)
        guard let account = self.account, account.privateKey != nil else { AppSheetsModel.shared.readOnlySheetVisible = true; return }
        guard !message.isEmpty else { return }

        let semanticMessage = semanticChatMessage(
            message: message,
            attributedMessage: attributedMessage
        )
        var content = replaceSemanticMentionsWithNpubs(semanticMessage)
        if SettingsStore.shared.replaceNsecWithHunter2Enabled {
            content = replaceNsecWithHunter2(content)
        }

        // @npub1... → nostr:npub1... and collect p-tags (same as post composer)
        let (contentNpubsReplaced, atNpubs) = replaceAtWithNostr(content)
        content = contentNpubsReplaced
        let atPtags = atNpubs.compactMap { Keys.hex(npub: $0) }

        // nostr:npub1... already in content
        let nostrNpubTags = getNostrNpubs(content).compactMap { Keys.hex(npub: $0) }

        var nEvent = NEvent(content: content)
        nEvent.kind = .chatMessage
        nEvent.tags.append(NostrTag(["a", aTag]))

        if let replyingTo {
            nEvent.tags.append(NostrTag(["e", replyingTo.id]))
        }
        else if let quoting {
            nEvent.tags.append(NostrTag(["q", quoting.id]))
        }

        // Mention p-tags so mentioned people get notifications
        let referencedPubkeys = [replyingTo?.pubkey, quoting?.pubkey].compactMap { $0 }
        for pubkey in Set(atPtags + nostrNpubTags + referencedPubkeys) {
            nEvent.tags.append(NostrTag(["p", pubkey]))
        }

        nEvent.publicKey = account.publicKey
                
        if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
            nEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
        }
        
        if account.isNC {
            nEvent = nEvent.withId()
            RemoteSignerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                // Save own chat to DB so reopen can load without relying only on relays
                Unpublisher.shared.publishNow(signedEvent, skipDB: false)
                sendNotification(.receivedMessage, NXRelayMessage(relays: "self", type: .EVENT, message: "", subscriptionId: "-DB-CHAT-", event: signedEvent))
            })
            
            clearMessage()
        }
        else {
            guard let signedEvent = try? account.signEvent(nEvent) else { return }
            // Save own chat to DB so reopen can load without relying only on relays
            Unpublisher.shared.publishNow(signedEvent, skipDB: false)
            sendNotification(.receivedMessage, NXRelayMessage(relays: "self", type: .EVENT, message: "", subscriptionId: "-DB-CHAT-", event: signedEvent))
            clearMessage()
        }
    }

    private func mentionChoices(for term: String, account: CloudAccount) -> [NRContact] {
        let terms = SearchModel.normalizedTerms(term)
        let allowedPubkeys = account.followingPubkeys.union(account.privateFollowingPubkeys)
        var seen = Set<String>()

        // messages is newest-first: room participants naturally retain recency priority.
        let recentContacts = chatVM.messages.compactMap { row -> NRContact? in
            guard seen.insert(row.pubkey).inserted else { return nil }
            return row.nrContact
        }

        let searchedContacts = terms.isEmpty ? [] : mentionSearchResults.filter {
            allowedPubkeys.contains($0.pubkey) && seen.insert($0.pubkey).inserted
        }

        return (recentContacts + searchedContacts)
            .filter {
                terms.isEmpty || SearchModel.matches(
                    terms: terms,
                    searchableValues: [
                        $0.anyName,
                        $0.fixedName,
                        $0.nip05
                    ].compactMap { $0 }
                )
            }
            .prefix(20)
            .map { $0 }
    }

    @MainActor
    private func refreshMentionChoices(
        for term: String,
        account: CloudAccount
    ) async {
        mentionSearchCancellationToken?.cancel()
        let cancellationToken = SearchCancellationToken()
        mentionSearchCancellationToken = cancellationToken
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else {
            mentionSearchResults = []
            return
        }

        let allowedPubkeys = account.followingPubkeys.union(account.privateFollowingPubkeys)
        let contactStage = await SearchModel.searchContacts(
            normalizedTerm,
            cancellationToken: cancellationToken
        )
        guard !Task.isCancelled,
              !cancellationToken.isCancelled,
              mentionSearchCancellationToken === cancellationToken else {
            return
        }
        mentionSearchResults = contactStage.contacts.filter {
            allowedPubkeys.contains($0.pubkey)
        }
    }

    private func selectMention(_ contact: NRContact, term selectedTerm: String) {
        mentionSearchCancellationToken?.cancel()
        mentionSearchCancellationToken = nil
        guard let completedMessage = completingChatMention(
            message: message,
            attributedMessage: attributedMessage,
            term: selectedTerm,
            name: contact.anyName,
            pubkey: contact.pubkey
        ) else { return }

        // Update both source-of-truth values synchronously. The UIKit editor then
        // receives this as an external attributed-text update; no coordinator
        // callback or marked-text timing is involved.
        attributedMessage = completedMessage
        message = completedMessage.string
    }

    private func clearMessage() {
        message = ""
        attributedMessage = NSAttributedString()
        clearComposerReference()
    }

    private func clearComposerReference() {
        replyingTo = nil
        quoting = nil
    }

    private func startTimer() { // Make sure real time sub for chat messages stays active
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            chatVM.updateLiveSubscription()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct PinnedChatMessages: View {
    @Environment(\.theme) private var theme

    let messages: [NRChatMessage]
    let canManage: Bool
    let onTap: (String) -> Void
    let onUnpin: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(messages) { message in
                    HStack(spacing: 6) {
                        Button {
                            onTap(message.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundColor(theme.accent)
                                MiniPFP(pictureUrl: message.nrContact.pictureUrl, size: 20)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(message.nrContact.anyName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(theme.accent)
                                        .lineLimit(1)
                                    Text(message.content ?? "Message")
                                        .font(.footnote)
                                        .foregroundColor(theme.primary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if canManage {
                            Button {
                                onUnpin(message.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundColor(theme.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Unpin message")
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .modifier {
                        if #available(iOS 26.0, *) {
                            $0.glassEffect(.clear.tint(theme.listBackground.opacity(0.35)))
                        }
                        else {
                            $0.background(theme.listBackground.opacity(0.92))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned messages")
    }
}

func semanticChatMessage(
    message: String,
    attributedMessage: NSAttributedString
) -> NSAttributedString {
    attributedMessage.string == message
        ? attributedMessage
        : NSAttributedString(string: message)
}

func completingChatMention(
    message: String,
    attributedMessage: NSAttributedString,
    term: String,
    name: String,
    pubkey: String
) -> NSAttributedString? {
    let result = attributedMessage.string == message
        ? NSMutableAttributedString(attributedString: attributedMessage)
        : NSMutableAttributedString(string: message)
    let nsMessage = message as NSString
    let token = "@\(term)"
    let tokenLength = (token as NSString).length
    guard tokenLength <= nsMessage.length else { return nil }

    let tokenRange = NSRange(
        location: nsMessage.length - tokenLength,
        length: tokenLength
    )
    guard nsMessage.substring(with: tokenRange) == token else { return nil }

    result.replaceCharacters(
        in: tokenRange,
        with: composerMention(
            name: name,
            pubkey: pubkey
        )
    )
    return result
}

private struct ChatMentionChoices: View {
    let contacts: [NRContact]
    let onSelect: (NRContact) -> Void

    var body: some View {
        if !contacts.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(contacts) { contact in
                        NRContactSearchResultRow(nrContact: contact) {
                            onSelect(contact)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 260)
            .padding(.horizontal, 10)
        }
    }
}

@available(iOS 18.0, *)
#Preview("Empty chatroom") {
    @Previewable @StateObject var chatVM = ChatRoomViewModel()

    PreviewContainer {
        Box {
            ChatRoom(aTag: "30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52", anonymous: false, chatVM: chatVM, selectedContact: .constant(nil))
                .environmentObject(ViewingContext(availableWidth: DIMENSIONS.articleRowImageWidth(UIScreen.main.bounds.width), fullWidthImages: false, viewType: .row))
        }
    }
}

@available(iOS 18.0, *)
#Preview("Chats and zaps") {
    @Previewable @StateObject var chatVM = ChatRoomViewModel()
    
    PreviewContainer({ pe in
        pe.loadLiveEvent()
        pe.loadNoDBChats()
    }){
        Box {
            ChatRoom(aTag: "30311:cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5:537a365c-f1ec-44ac-af10-22d14a7319fb", anonymous: false, chatVM: chatVM, selectedContact: .constant(nil))
//                .padding(10)
                .environmentObject(ViewingContext(availableWidth: DIMENSIONS.articleRowImageWidth(UIScreen.main.bounds.width), fullWidthImages: false, viewType: .row))
        }
    }
}
