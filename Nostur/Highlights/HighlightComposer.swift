//
//  HighlightComposer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/04/2023.
//

import SwiftUI
import NavigationBackport

struct HighlightComposer: View {
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    public var highlight: NewHighlight
    @State private var selectedAuthor: Contact?
    @State private var isAuthorSelectionShown = false
    @State private var activeAccount: CloudAccount? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if let account = activeAccount {
                VStack {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        InlineAccountSwitcher(activeAccount: account, onChange: { account in
                            activeAccount = account
                        }).equatable()

                        VStack(alignment:.leading, spacing: 3) {
                            HStack { // name + reply + context menu
                                PostHeaderView(pubkey: account.publicKey, name: account.anyName, via: "Nostur", createdAt: .now, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: true)
                                Spacer()
                            }

                            
                            VStack {
                                Text(highlight.selectedText)
                                    .italic()
                                    .padding(20)
                                    .overlay(alignment:.topLeading) {
                                        Image(systemName: "quote.opening")
                                            .foregroundColor(Color.secondary)
                                    }
                                    .overlay(alignment:.bottomTrailing) {
                                        Image(systemName: "quote.closing")
                                            .foregroundColor(Color.secondary)
                                    }
                                
                                if let selectedAuthor = selectedAuthor {
                                    HStack {
                                        Spacer()
                                        PFP(pubkey: selectedAuthor.pubkey, contact: selectedAuthor, size: 20)
                                        Text(selectedAuthor.authorName)
                                    }
                                    .padding(.trailing, 40)
                                }
                                HStack {
                                    Spacer()
                                    if let md = try? AttributedString(markdown:"[\(highlight.url)](\(highlight.url))") {
                                        Text(md)
                                            .lineLimit(1)
                                            .font(.caption)
                                    }
                                }
                                .padding(.trailing, 40)
                            }
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(.regularMaterial, lineWidth: 1)
                            )
                            CustomizablePreviewFooterFragmentView()
                        }
                    }
                    .padding(10)
                    Divider()
                    Spacer()
                }
                .padding(.top, 20)
                .navigationTitle(String(localized:"Share highlight", comment:"Navigation title for screen to Share a Highlighted Text"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack {
                            if selectedAuthor != nil {
                                Button(String(localized:"Remove author", comment: "Button to Remove author from Highlight")) { selectedAuthor = nil }
                            }
                            else {
                                Button(String(localized:"Include author", comment: "Button to include author in Highlight")) { isAuthorSelectionShown = true }
                            }
                            Button(String(localized:"Post.verb", comment: "Button to post a highlight")) { send() }
                                .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                        }
                    }
                }
                .sheet(isPresented: $isAuthorSelectionShown) {
                    NBNavigationStack {
                        ContactsSearch(followingPubkeys: follows(),
                                       prompt: "Search", onSelectContact: { selectedContact in
                            selectedAuthor = selectedContact
                            isAuthorSelectionShown = false
                        })
                        .equatable()
                        .environmentObject(themes)
                        .navigationTitle(String(localized:"Find author", comment:"Navigation title of Find author screen"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    isAuthorSelectionShown = false
                                }
                            }
                        }
                    }
                    .nbUseNavigationStack(.never)
                    .presentationBackgroundCompat(themes.theme.listBackground)
                }
            }
        }
        .onAppear {
            activeAccount = la.account
        }
    }
    
    // TODO: Need to move to NewPostModel
    func send() {
        guard let account = activeAccount else { return }
        guard isFullAccount(account) else { showReadOnlyMessage(); return }
        var nEvent = NEvent(content: highlight.selectedText)
        nEvent.publicKey = account.publicKey
        nEvent.createdAt = NTimestamp.init(date: Date())
        nEvent.kind = .highlight
        if let selectedAuthor = selectedAuthor {
            nEvent.tags.append(NostrTag(["p", selectedAuthor.pubkey]))
        }
        nEvent.tags.append(NostrTag(["r", highlight.url]))
        
        if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
            nEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
        }
                
        let cancellationId = UUID()
        if account.isNC {
            nEvent = nEvent.withId()
            
            // Save unsigned event:
            let bgContext = bg()
            bgContext.perform {
                let savedEvent = Event.saveEvent(event: nEvent, flags: "nsecbunker_unsigned", context: bgContext)
                savedEvent.cancellationId = cancellationId
                DispatchQueue.main.async {
                    sendNotification(.newPostSaved, savedEvent)
                }
                DataProvider.shared().bgSave()
                dismiss()
                DispatchQueue.main.async {
                    NSecBunkerManager.shared.setAccount(account)
                    NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                        bgContext.perform {
                            savedEvent.sig = signedEvent.signature
                            savedEvent.flags = "awaiting_send"
                            savedEvent.cancellationId = cancellationId
                            ViewUpdates.shared.updateNRPost.send(savedEvent)
//                            savedEvent.updateNRPost.send(savedEvent)
                            DispatchQueue.main.async {
                                _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                            }
                        }
                    })
                }
            }
        }
        else if let signedEvent = try? account.signEvent(nEvent) {
            let bgContext = bg()
            bgContext.perform {
                let savedEvent = Event.saveEvent(event: signedEvent, flags: "awaiting_send", context: bgContext)
                savedEvent.cancellationId = cancellationId
                DataProvider.shared().bgSave()
                dismiss()
                if ([1,6,20,9802,30023,34235].contains(savedEvent.kind)) {
                    DispatchQueue.main.async {
                        sendNotification(.newPostSaved, savedEvent)
                    }
                }
            }
            _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
        }
    }
}

import NavigationBackport

#Preview("Highlight composer") {
    let example = NewHighlight(url: "https://nostur.com", selectedText: "This is amazing, this is some text that is being highlighted by Nostur highlightur", title:"Nostur - a nostr client for iOS/macOS")
            
    return PreviewContainer {
        NBNavigationStack {
            HighlightComposer(highlight: example)
        }
    }
}

