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
    
    private let nrPost: NRPost
    private var rootDismiss: (() -> Void)?
    
    @State private var isOwnPost = false
    @State private var isFullAccount = false
    
    @State private var postId: String = ""
    @State private var url: String = ""
    @State private var pubkeysInPost: Set<String> = []
    
    @State private var rawSource: String? = nil
    
    @ObservedObject private var footerAttributes: FooterAttributes
    
    init(nrPost: NRPost, rootDismiss: (() -> Void)? = nil) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.rootDismiss = rootDismiss
    }
    
    var body: some View {
        NXList {
            Section(header: Text("Nostr ID")) {
                CopyableTextView(text: postId, copyText: "nostr:\(postId)")
                    .foregroundColor(theme.accent)
                    .lineLimit(1)
            }
            .listRowBackground(theme.background)
            
            Section(header: Text("Link")) {
                CopyableTextView(text: url)
                    .foregroundColor(theme.accent)
                    .lineLimit(1)
            }
            .listRowBackground(theme.background)
            
            Section {
                Button(action: {
                    if let rawSource {
                        UIPasteboard.general.string = rawSource
                    }
                    rootDismiss?()
                }) {
                    Label("Copy raw JSON", systemImage: "ellipsis.curlybraces")
                        .foregroundColor(theme.accent)
                }
                
                NavigationLink {
                    PostRawJSONSheet(nrPost: nrPost, rootDismiss: rootDismiss)
                } label: {
                    Label("Show raw JSON", systemImage: "doc.text.magnifyingglass")
                        .foregroundColor(theme.accent)
                }
                
                if nrPost.isRestricted && isOwnPost && isFullAccount {
                    NavigationLink {
                        RepublishRestrictedPostSheet(nrPost: nrPost, rootDismiss: rootDismiss)
                            .environmentObject(la)
                    } label: {
                        Label(String(localized: "Republish", comment: "Button to republish a post different relay(s)"), systemImage: "dot.radiowaves.left.and.right")
                            .foregroundColor(theme.accent)
                    }
                }
                else if !nrPost.isRestricted && !(nrPost.isPrivate && !isOwnPost) {
                    NavigationLink {
                        RepublishPostSheet(nrPost: nrPost, rootDismiss: rootDismiss)
                            .environmentObject(la)
                    } label: {
                        if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey {
                            Label(String(localized: "Republish", comment: "Button to republish a post different relay(s)"), systemImage: "dot.radiowaves.left.and.right")
                                .foregroundColor(theme.accent)
                        }
                        else {
                            Label(String(localized: "Republish", comment: "Button to republish a post different relay(s)"), systemImage: "dot.radiowaves.left.and.right")
                                .foregroundColor(theme.accent)
                        }
                    }
                }
            }
            .listRowBackground(theme.background)
            
            if pubkeysInPost.count > 1 {
                Section {
                    NavigationLink {
                        AddContactsToListSheet(preSelectedContactPubkeys: pubkeysInPost, rootDismiss: rootDismiss)
                            .environment(\.managedObjectContext, viewContext())
                    } label: {
                        Label(String(localized:"Add \(pubkeysInPost.count) contacts to List", comment: "Post context menu button"), systemImage: "person.2.crop.square.stack")
                            .foregroundColor(theme.accent)
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
                    if AccountsState.shared.activeAccountPublicKey == nrPost.pubkey || nrPost.flags == "sent" {
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
        
        .onAppear {
            isOwnPost = nrPost.pubkey == la.pubkey
            self.isFullAccount = la.account.isFullAccount
            loadId()
            loadPubkeysInPost()
        }
        .task {
            await loadRawSource()
        }
        
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    rootDismiss?()
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
                let isUnsigned = event.flags == "nsecbunker_unsigned"
                let nEvent = event.toNEvent()
                
                if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey && isUnsigned && isNC {
                    Task { @MainActor in
                        RemoteSignerManager.shared.requestSignature(forEvent: nEvent, usingAccount: la.account,  whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                }
                else {
                    Unpublisher.shared.publishNow(nEvent)
                }
            }
        }
    }
}

struct PostRawJSONTextView: UIViewRepresentable {
    let text: String
    let textColor: Color
    let accentColor: Color
    
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.textContainer.lineFragmentPadding = 0
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .regular
        )
        view.adjustsFontForContentSizeCategory = true
        updateUIView(view, context: context)
        return view
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = UIColor(textColor)
        uiView.tintColor = UIColor(accentColor)
    }
}

struct PostRawJSONSheet: View {
    @Environment(\.theme) private var theme
    
    private let nrPost: NRPost
    private let rootDismiss: (() -> Void)?
    
    @State private var rawSource: String? = nil
    
    init(nrPost: NRPost, rootDismiss: (() -> Void)? = nil) {
        self.nrPost = nrPost
        self.rootDismiss = rootDismiss
    }
    
    var body: some View {
        Group {
            if let rawSource {
                PostRawJSONTextView(
                    text: rawSource,
                    textColor: theme.primary,
                    accentColor: theme.accent
                )
            }
            else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
        }
        .background(theme.listBackground)
        .navigationTitle("Raw JSON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    rootDismiss?()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    if let rawSource {
                        UIPasteboard.general.string = rawSource
                    }
                }
                .disabled(rawSource == nil)
            }
        }
        .task {
            rawSource = await withBgContext { _ in
                return nrPost.event?.toNEvent().eventJson([.prettyPrinted, .withoutEscapingSlashes])
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
