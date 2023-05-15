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
    let up:Unpublisher = .shared
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
            .navigationTitle("Share highlight")
    //        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if selectedAuthor != nil {
                            Button("Remove author") { selectedAuthor = nil }
                        }
                        else {
                            Button("Include author") { isAuthorSelectionShown = true }
                        }
                        Button("Post") { send() }
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
                    .navigationTitle("Find author")
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
            nEvent.tags.append(NEventTag(type: "p", otherInformation: selectedAuthor.pubkey))
        }
        nEvent.tags.append(NEventTag(type: "r", otherInformation: highlight.url))
        
        if let signedEvent = try? ns.signEvent(nEvent) {
            up.publishNow(signedEvent)
            //                        noteCancellationId = up.publish(signedEvent)
            dismiss()
        }
    }
}

struct HighlightComposer_Previews: PreviewProvider {
    static var previews: some View {
        let example = NewHighlight(url: "https://nostur.com", selectedText: "This is amazing, this is some text that is being highlighted by Nostur highlightur", title:"Nostur - a nostr client for iOS/macOS")
        
        NavigationStack {
            HighlightComposer(highlight: example)
        }
        .withPreviewEnvironment()
    }
}
