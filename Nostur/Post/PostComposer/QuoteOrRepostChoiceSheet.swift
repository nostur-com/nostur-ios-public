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
    
    var body: some View {
        // repost
        HStack(alignment: .center, spacing: 20) {
            
            Group {
                Button(String(localized:"Repost", comment:"Button to Repost a post"), systemImage: "arrow.2.squarepath") {
                    self.repost()
                    dismiss()
                }
                
                Button(String(localized: "Quote", comment:"Button to Quote a post"), systemImage: "square.and.pencil") {
                    self.quoteThisPost()
                    dismiss()
                }
            }
//            .buttonStyleGlassProminent()
            .buttonStyleGlassProminent(tint: theme.accent)
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
                Button("Cancel", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        
    }
    
    private func repost() {
        guard let account = account() else { return }
        guard isFullAccount(account) else { showReadOnlyMessage(); return }
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
