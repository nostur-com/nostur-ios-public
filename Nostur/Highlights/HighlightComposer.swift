//
//  HighlightComposer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/04/2023.
//

import SwiftUI

struct HighlightComposer: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var ns:NosturState
    var highlight:NewHighlight
    @State var selectedAuthor:Contact?
    @State var isAuthorSelectionShown = false
    
    var body: some View {
        if let account = ns.account {
            VStack {
                HStack(alignment: .top, spacing:0) {
                    PFP(pubkey: account.publicKey, account: account)
                        .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                        .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)

                    VStack(alignment:.leading, spacing: 3) {
                        HStack { // name + reply + context menu
                            PreviewHeaderView(authorName: account.display_name, username: account.name, nip05verified: !account.nip05.isEmpty)
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
                        PreviewFooterFragmentView()
                    }
                    .padding(.trailing, 10)
                }
                    .padding(10)
                    .boxShadow()
                    .padding(10)
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
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .sheet(isPresented: $isAuthorSelectionShown) {
                NavigationStack {
                    ContactsSearch(followingPubkeys:NosturState.shared.followingPublicKeys,
                                   prompt: "Search", onSelectContact: { selectedContact in
                        selectedAuthor = selectedContact
                        isAuthorSelectionShown = false
                    })
                    .equatable()
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
            }
        }
    }
    
    func send() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        var nEvent = NEvent(content: highlight.selectedText)
        nEvent.createdAt = NTimestamp.init(date: Date())
        nEvent.kind = .highlight
        if let selectedAuthor = selectedAuthor {
            nEvent.tags.append(NostrTag(["p", selectedAuthor.pubkey]))
        }
        nEvent.tags.append(NostrTag(["r", highlight.url]))
        
        if let signedEvent = try? ns.signEvent(nEvent) {
            Unpublisher.shared.publishNow(signedEvent)
            dismiss()
        }
    }
}

struct HighlightComposer_Previews: PreviewProvider {
    static var previews: some View {
        let example = NewHighlight(url: "https://nostur.com", selectedText: "This is amazing, this is some text that is being highlighted by Nostur highlightur", title:"Nostur - a nostr client for iOS/macOS")
        
        PreviewContainer {
            NavigationStack {
                HighlightComposer(highlight: example)
            }
        }
    }
}
