//
//  PostDetailsMenuSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct PostDetailsMenuSheet: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    public let nrPost: NRPost
    public var onDismiss: (() -> Void)?
    
    @State private var isOwnPost = false
    @State private var isFullAccount = false
    @State private var showRepublishSheet = false
    
    @State private var postId: String = ""
    @State private var url: String = ""
    @State private var pubkeysInPost: Set<String> = []
    
    @State private var rawSource: String? = nil
    
    @ObservedObject private var footerAttributes: FooterAttributes
    
    init(nrPost: NRPost, onDismiss: (() -> Void)? = nil) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        List {
            Section(header: Text("Nostr ID")) {
                CopyableTextView(text: postId, copyText: "nostr:\(postId)")
                    .lineLimit(1)
            }
            .listRowBackground(theme.background)
            
            Section(header: Text("Link")) {
                CopyableTextView(text: url)
                    .lineLimit(1)
            }
            .listRowBackground(theme.background)
            
            Section {
                Button(action: {
                    if let rawSource {
                        UIPasteboard.general.string = rawSource
                    }
                    onDismiss?()
                }) {
                    Label("Copy raw JSON", systemImage: "ellipsis.curlybraces")
                }
                
                if nrPost.isRestricted && isOwnPost && isFullAccount {
                    Button {
                       showRepublishSheet = true
                    } label: {
                        Label(String(localized:"Republish to different relay(s)", comment: "Button to republish a post different relay(s)"), systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                else {
                    Button {
                       rebroadcast()
                    } label: {
                        if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey {
                            Label(String(localized:"Rebroadcast to relays (again)", comment: "Button to broadcast own post again"), systemImage: "dot.radiowaves.left.and.right")
                        }
                        else {
                            Label(String(localized:"Rebroadcast to relays", comment: "Button to rebroadcast a post"), systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                }
            }
            .listRowBackground(theme.background)
            
            if pubkeysInPost.count > 1 {
                Section {
                    
                    Button {
                        onDismiss?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY + 0.35) { // Short delay freezes????
                            AppSheetsModel.shared.addContactsToListInfo = AddContactsToListInfo(pubkeys: pubkeysInPost)
                        }
                    } label: {
                        Label(String(localized:"Add \(pubkeysInPost.count) contacts to List", comment: "Post context menu button"), systemImage: "person.2.crop.square.stack")
                    }
                    
                } footer: {
                    Text("Contacts from this post")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .listRowBackground(theme.background)
            }
            
            if !footerAttributes.relays.isEmpty {
                VStack(alignment: .leading) {
                    if let via = nrPost.via {
                        Text("Posted via \(via)", comment: "Showing from which app this post was posted")
                            .lineLimit(1)
                    }
                    if AccountsState.shared.activeAccountPublicKey == nrPost.pubkey {
                        Text("Sent to:", comment:"Heading for list of relays sent to")
                    }
                    else {
                        Text("Received from:", comment:"Heading for list of relays received from")
                    }
                    ForEach(footerAttributes.relays.sorted(by: <), id: \.self) { relay in
                        Text(String(relay)).lineLimit(1)
                    }
                }
                .foregroundColor(.gray)
                .listRowBackground(theme.background)
            }
        }
        
        
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .nbNavigationDestination(isPresented: $showRepublishSheet) {
            RepublishRestrictedPostSheet(nrPost: nrPost, onDismiss: { dismiss() })
                .environmentObject(la)
        }
        
        .onAppear {
            isOwnPost = nrPost.pubkey == la.pubkey
            self.isFullAccount = la.account.isFullAccount
            loadId()
        }
        .task {
            await loadRawSource()
        }
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onDismiss?() }) {
                    Text("Done")
                }
            }
        }
    }
    
    private func loadPubkeysInPost() {
        let onlyPtags: [String] = nrPost.fastTags.compactMap({ fastTag in
            if (fastTag.0 != "p" || !isValidPubkey(fastTag.1)) { return nil }
            return fastTag.1
        })
        let pTagPubkeys: Set<String> = Set(onlyPtags).union([nrPost.pubkey])
        pubkeysInPost = pTagPubkeys
    }
    
    private func loadId() {
        let relaysForHint: Set<String> = resolveRelayHint(forPubkey: nrPost.pubkey, receivedFromRelays: nrPost.footerAttributes.relays)
        
        if nrPost.kind >= 30000 && nrPost.kind < 40000 {
            if let si = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(nrPost.kind), pubkey: nrPost.pubkey, dTag: nrPost.dTag, relays: Array(relaysForHint)) {
                postId = si.identifier
                url = "https://njump.me/\(si.identifier)"
            }
        }
        else {
            if let si = try? NostrEssentials.ShareableIdentifier("nevent", id: nrPost.id, kind: Int(nrPost.kind), pubkey: nrPost.pubkey, relays: Array(relaysForHint)) {
                postId = si.identifier
                url = "https://njump.me/\(si.identifier)"
            }
        }
    }
    
    private func loadRawSource() async {
        rawSource = await withBgContext { _ in
            return nrPost.event?.toNEvent().eventJson()
        }
    }
    
    private func rebroadcast() {
        let isNC = la.account.isNC
        bg().perform {
            if let event = nrPost.event {
                
                let nEvent = event.toNEvent()
                
                if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey && event.flags == "nsecbunker_unsigned" && isNC {
                    NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: la.account,  whenSigned: { signedEvent in
                        Unpublisher.shared.publishNow(signedEvent)
                    })
                }
                else {
                    Unpublisher.shared.publishNow(nEvent)
                }
            }
        }
    }
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            PostDetailsMenuSheet(nrPost: testNRPost())
        }
    }
}
