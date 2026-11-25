//
//  QuoteOrRepostChoiceSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/03/2023.
//

import SwiftUI

struct QuoteOrRepostChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    
    public let quoteOrRepost: QuoteOrRepost
    @Binding public var quotePost: QuotePost?
    @State private var repostTask: Task<Void, Never>?
    @State private var repostFailed = false
    
    var body: some View {
        // repost
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 20) {
                Group {
                    Button(String(localized:"Repost", comment:"Button to Repost a post"), systemImage: "arrow.2.squarepath") {
                        self.repost()
                    }

                    Button(String(localized: "Quote", comment:"Button to Quote a post"), systemImage: "square.and.pencil") {
                        self.quoteThisPost()
                        dismiss()
                    }
                }
                .buttonStyleGlassProminent(tint: theme.accent)
                .disabled(repostTask != nil)
            }
            if repostTask != nil {
                ProgressView("Reposting…")
                    .font(.footnote)
            } else if repostFailed {
                Text("Couldn’t repost. Try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.large)
        .fontWeightBold()
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .vCentered()
        .navigationTitle("Repost or quote this post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", role: .cancel) {
                    dismiss()
                }
            }
        }
        .onDisappear { repostTask?.cancel() }
        
    }
    
    @MainActor private func repost() {
        guard let account = account() else { dismiss(); return }
        guard isFullAccount(account) else { showReadOnlyMessage(); dismiss(); return }
        if let target = PostProofOfWork.configuredTarget {
            repostWithProof(account: account, target: target)
            return
        }
        dismiss()
        Importer.shared.delayProcessing()
        let accountPublicKey = account.publicKey
        let cancellationId = UUID()
        let bgContext = bg()
        if account.isNC {
            bgContext.perform {
                guard let bgEvent = quoteOrRepost.nrPost.event else { return }
                let originalNEvent = bgEvent.toNEvent()
                
                // 1. create repost
                var repost = EventMessageBuilder.makeRepost(original: bgEvent, embedOriginal: true)
                repost.publicKey = accountPublicKey
                
                if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(repost.publicKey)) {
                    repost.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
                }
                
                repost = repost.withId()
                
                let savedEvent = Event.saveEvent(event: repost, flags: "nsecbunker_unsigned", context: bgContext)
                savedEvent.cancellationId = cancellationId
                DispatchQueue.main.async {
                    sendNotification(.newPostSaved, savedEvent)
                }
                DataProvider.shared().saveToDiskNow(.bgContext)
                
                DispatchQueue.main.async {
                    RemoteSignerManager.shared.requestSignature(forEvent: repost, usingAccount: account, whenSigned: { signedEvent in
                        bg().perform {
                            savedEvent.sig = signedEvent.signature
                            savedEvent.flags = "awaiting_send"
                            savedEvent.cancellationId = cancellationId
                            ViewUpdates.shared.updateNRPost.send(savedEvent)
                            DispatchQueue.main.async {
                                Unpublisher.shared.publishNow(originalNEvent) // publish original
                                _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                                
                                sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: originalNEvent.id))
                            }
                        }
                    })
                }
            }
        }
        else {
            // 1. create repost
            bgContext.perform {
                guard let bgEvent = quoteOrRepost.nrPost.event else { return }
                var repost = EventMessageBuilder.makeRepost(original: bgEvent, embedOriginal: true)
                repost.publicKey = accountPublicKey
                
                if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(repost.publicKey)) {
                    repost.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
                }
                
                repost = repost.withId()
                
                Task { @MainActor in
                    if let signedEvent = try? account.signEvent(repost) {
                        bgContext.perform {
                            let originalNEvent = bgEvent.toNEvent()
                            let savedEvent = Event.saveEvent(event: signedEvent, flags: "awaiting_send", context: bgContext)
                            savedEvent.cancellationId = cancellationId
                            
                            DataProvider.shared().saveToDiskNow(.bgContext)
                            if ([1,1111,1222,1244,6,20,9802,30023,34235].contains(savedEvent.kind)) {
                                DispatchQueue.main.async {
                                    sendNotification(.newPostSaved, savedEvent)
                                }
                            }
                            Unpublisher.shared.publishNow(originalNEvent) // publish original
                            _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                            Task { @MainActor in
                                sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: originalNEvent.id))
                            }
                        }
                        
                    }
                }
            }
        }
    }

    @MainActor
    private func repostWithProof(account: CloudAccount, target: Int) {
        guard repostTask == nil else { return }
        repostFailed = false
        let post = quoteOrRepost.nrPost
        let pubkey = account.publicKey
        let includeClientTag = SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(pubkey)
        repostTask = Task { @MainActor in
            defer { repostTask = nil }
            do {
                let events: (repost: NEvent, original: NEvent)? = await withBgContext { _ in
                    guard let original = post.event else { return nil }
                    var repost = EventMessageBuilder.makeRepost(original: original, embedOriginal: true)
                    repost.publicKey = pubkey
                    if includeClientTag { repost.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE])) }
                    return (repost, original.toNEvent())
                }
                guard let events else { throw SignError.signingFailure }
                let mined = try await PostProofOfWork.mine(events.repost, target: target)
                let signed = try await signMinedEvent(mined, account: account)
                queueRepost(signed, original: events.original)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                repostFailed = true
            }
        }
    }

    @MainActor
    private func queueRepost(_ signed: NEvent, original: NEvent) {
        let cancellationId = UUID()
        let context = bg()
        context.perform {
            let saved = Event.saveEvent(event: signed, flags: "awaiting_send", context: context)
            saved.cancellationId = cancellationId
            DataProvider.shared().saveToDiskNow(.bgContext)
            DispatchQueue.main.async {
                sendNotification(.newPostSaved, saved)
            }
        }
        Unpublisher.shared.publishNow(original)
        _ = Unpublisher.shared.publish(signed, cancellationId: cancellationId)
        sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: original.id))
    }
    
    private func quoteThisPost() {
        quotePost = QuotePost(nrPost: quoteOrRepost.nrPost)
    }
}

@available(iOS 17.0, *)
#Preview {
    
    @Previewable @State var quotePost: QuotePost? = nil
    @Previewable @State var quoteOrRepost: QuoteOrRepost? = QuoteOrRepost(nrPost: testNRPost())
    
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        VStack {
            
        }
        .sheet(item: $quoteOrRepost) { quoteOrRepost in
            NRSheetNavigationStack {
                QuoteOrRepostChoiceSheet(quoteOrRepost: quoteOrRepost, quotePost: $quotePost)
                    
            }
            .presentationDetents200()
            .presentationDragIndicatorVisible()
        }
    }
}
