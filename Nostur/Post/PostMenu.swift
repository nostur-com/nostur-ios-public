//
//  PostMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/05/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct PostMenu: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    public let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @Environment(\.dismiss) private var dismiss
    private let NEXT_SHEET_DELAY = 0.05
    @State private var followToggles = false
    @State private var blockOptions = false
    @State private var pubkeysInPost: Set<String> = []
    
    @State private var showMultiFollowSheet = false
    @State private var showContactSubMenu = false
    @State private var showContactBlockSubMenu = false
    @State private var showPostDetailsSubMenu = false
    @State private var showPostShareSheet = false
    
    @State private var isOwnPost = false
    @State private var isFollowing = false
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
    }
    
    var body: some View {
        List {
            
            if isOwnPost {
                // Delete button
                Button(role: .destructive, action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.requestDeletePost, nrPost.id)
                    }
                }) {
                    Label(String(localized:"Delete", comment:"Post context menu action to Delete a post"), systemImage: "trash")
                        .foregroundColor(theme.accent)
                }
                
                Button(action: {
                    
                }) {
                    Label("Pin to your profile", systemImage: "pin")
                        .foregroundColor(theme.accent)
                }
                
                Button(action: {
                    
                }) {
                    Label("Add/remove from Highlights", systemImage: "star")
                        .foregroundColor(theme.accent)
                }
            }
            
            Section {
                if !isOwnPost {
                    self.followButton
                }
                
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY + 0.35) { // Short delay freezes????
                        sendNotification(.addRemoveToListsheet, nrPost.contact)
                    }
                }) {
                    Label("Add/remove from Lists", systemImage: "person.2.crop.square.stack")
                        .foregroundColor(theme.accent)
                }
        
                if !isOwnPost {
                    Button(action: {
                        dismiss()
                        sendNotification(.clearNavigation)
                        sendNotification(.showingSomeoneElsesFeed, nrPost.contact)
                    }) {
                        Label {
                            Text("Show \(nrContact.anyName)'s feed", comment: "Menu button to show someone's feed")
                                .foregroundColor(theme.accent)
                        } icon: {
                            ObservedPFP(nrContact: nrContact, size: 20)
                        }
                    }
                }
            }
            .listRowBackground(theme.background)
            
            
            
            Section {
                Button(action: {
                    showContactBlockSubMenu = true
                }) {
                    Label("Block \(nrContact.anyName)", systemImage: "circle.slash")
                        .foregroundColor(theme.accent)
                }
                
                Button(action: {
                    dismiss()
                    L.og.debug("Mute conversation")
                    mute(eventId: nrPost.id, replyToRootId: nrPost.replyToRootId, replyToId: nrPost.replyToId)
                }) {
                    Label("Mute", systemImage: "bell.slash")
                        .foregroundColor(theme.accent)
                }
                
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.reportPost, nrPost)
                    }
                } label: {
                    Label(String(localized:"Report.verb", comment:"Post context menu action to Report a post or user"), systemImage: "flag")
                        .foregroundColor(theme.accent)
                }
            }
            .listRowBackground(theme.background)
            
            
            Button(action: {
                showPostShareSheet = true
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .foregroundColor(theme.accent)
            }
            .listRowBackground(theme.background)
            
            Button {
                dismiss()
                if let pn = Event.fetchEvent(id: nrPost.id, context: viewContext())?.privateNote {
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.editingPrivateNote, pn)
                    }
                }
                else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.newPrivateNoteOnPost, nrPost.id)
                    }
                }
            } label: {
                Label(String(localized:"Add private note to post", comment: "Post context menu button"), systemImage: "note.text")
                    .foregroundColor(theme.accent)
            }
            .listRowBackground(theme.background)

            Button(action: {
                showPostDetailsSubMenu = true
            }) {
                Label("Post details", systemImage: "info.circle")
                    .foregroundColor(theme.accent)
                
            }
            .listRowBackground(theme.background)
            
        }

        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .onAppear {
            isOwnPost = nrPost.pubkey == la.pubkey
        }
        
        .nbNavigationDestination(isPresented: $showMultiFollowSheet) {
            MultiFollowSheet(pubkey: nrPost.pubkey, name: nrPost.anyName, onDismiss: { dismiss() })
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen usage (for bg)
                .background(theme.listBackground)
                .environment(\.theme, theme)
        }
        .nbNavigationDestination(isPresented: $showContactBlockSubMenu) {
            PostMenuBlockOptions(nrContact: nrPost.contact, onDismiss: { dismiss() })
                .environment(\.theme, theme)
        }
        .nbNavigationDestination(isPresented: $showContactSubMenu) {
            List {
                Button(role: .destructive, action: {
                    showContactBlockSubMenu = true
                }) {
                    Label("Block", systemImage: "square.and.arrow.up")
                }
                // Delete button
                Button(role: .destructive, action: {
                    
                }) {
                    Label("Follow", systemImage: "trash")
                }
            }
            
        }
        .nbNavigationDestination(isPresented: $showPostShareSheet) {
            PostMenuShareSheet(nrPost: nrPost, onDismiss: { dismiss() })
        }
        .nbNavigationDestination(isPresented: $showPostDetailsSubMenu) {
            PostDetailsMenuSheet(nrPost: nrPost, onDismiss: { dismiss() })
                .environmentObject(la)
        }
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { dismiss() }) {
                    Text("Done")
                }
            }
        }
        
    }
    
    @ViewBuilder
    private var followButton: some View {
        Button(action: {
            guard isFullAccount() else {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)  {
                    showReadOnlyMessage()
                }
                return
            }
            dismiss()
            if isFollowing {
                la.unfollow(nrPost.pubkey)
                isFollowing = false
            }
            else {
                la.follow(nrPost.pubkey)
            }
        }) {
            if isFollowing {
                Label(String(localized:"Unfollow \(nrPost.anyName)", comment: "Post context menu button to Unfollow (name)"), systemImage: "person.badge.minus")
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading) // Needed do List row tap area doesn't cover long tap
                    .contentShape(Rectangle())
            }
            else {
                Label(String(localized:"Follow \(nrPost.anyName)", comment: "Post context menu button to Follow (name)"), systemImage: "person.badge.plus")
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading) // Needed do List row tap area doesn't cover long tap
                    .contentShape(Rectangle())
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    showMultiFollowSheet = true
                }
        )
        .onAppear {
            isFollowing = Nostur.isFollowing(nrPost.pubkey)
        }
    }
}

struct PostMenuBlockOptions: View {
    @Environment(\.theme) private var theme
    
    @ObservedObject var nrContact: NRContact
    
    public var onDismiss: (() -> Void)?

    var body: some View {
        Form {
            Section("") {
                Group {
                    Button("Block") { block(pubkey: nrContact.pubkey, name: nrContact.anyName); onDismiss?() }
                    Button("Block for 1 hour") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 1, name: nrContact.anyName); onDismiss?() }
                    Button("Block for 4 hours") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 4, name: nrContact.anyName); onDismiss?() }
                    Button("Block for 8 hours") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 8, name: nrContact.anyName); onDismiss?() }
                    Button("Block for 1 day") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 24, name: nrContact.anyName); onDismiss?() }
                    Button("Block for 1 week") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 24*7, name: nrContact.anyName); onDismiss?() }
                    Button("Block for 1 month") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 24*31, name: nrContact.anyName); onDismiss?() }
                }
                .buttonStyle(.borderless)
                .foregroundColor(theme.accent)
            }
            .listRowBackground(theme.listBackground)

        }
        
        .scrollContentBackgroundHidden()
        .background(theme.background)
        .navigationTitle("Block \(nrContact.anyName)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PostMenuShareSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    public let nrPost: NRPost
    public var onDismiss: (() -> Void)?
    
    @State private var postId: String = ""
    @State private var url: String = ""
    
    var body: some View {
        List {
            Section(header: Text("Nostr ID")) {
                CopyableTextView(text: postId, copyText: "nostr:\(postId)")
                    .lineLimit(1)
            }
            Section(header: Text("Link")) {
                CopyableTextView(text: url)
                    .lineLimit(1)
            }
            
            Section {
                Button(action: {
                    onDismiss?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.shareWeblink, nrPost)
                    }
                }) {
                    Label("Share link", systemImage: "link")
                }
                
                if #available(iOS 16, *), nrPost.kind != 30023 {
                    Button(action: {
                        onDismiss?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.sharePostScreenshot, nrPost)
                        }
                    }) {
                        Label("Share screenshot", systemImage: "photo")
                    }
                }
            }
        }
        .onAppear {
            loadId()
        }
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onDismiss?() }) {
                    Text("Done")
                }
            }
        }
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
}

struct PostDetailsMenuSheet: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    public let nrPost: NRPost
    public var onDismiss: (() -> Void)?
    
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
            Section(header: Text("Link")) {
                CopyableTextView(text: url)
                    .lineLimit(1)
            }
            
            Section {
                Button(action: {
                    if let rawSource {
                        UIPasteboard.general.string = rawSource
                    }
                    onDismiss?()
                }) {
                    Label("Copy raw JSON", systemImage: "ellipsis.curlybraces")
                }
                
                Button {
                   rebroadcast()
                } label: {
                    if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey {
                        Label(String(localized:"Rebroadcast to relays(again)", comment: "Button to broadcast own post again"), systemImage: "dot.radiowaves.left.and.right")
                    }
                    else {
                        Label(String(localized:"Rebroadcast to relays", comment: "Button to rebroadcast a post"), systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }
            
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
        .onAppear {
            loadId()
            loadRawSource()
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
    
    private func loadRawSource() {
        bg().perform {
            if let sourceCode = nrPost.event?.toNEvent().eventJson() {
                Task { @MainActor in
                    self.rawSource = sourceCode
                }
            }
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

let NEXT_SHEET_DELAY = 0.05

struct PostMenuButton: View {
    @Environment(\.theme) private var theme
    var nrPost: NRPost
    
    var body: some View {
        Image(systemName: "ellipsis")
            .fontWeightBold()
            .foregroundColor(theme.footerButtons)
            .padding(.leading, 15)
            .padding(.bottom, 14)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .contentShape(Rectangle())
            .padding(.top, -10)
            .padding(.trailing, -10)
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        sendNotification(.showNoteMenu, nrPost)
                    }
            )
    }
}

#Preview("Post Menu") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    PostMenu(nrPost: nrPost)
                        .environment(\.theme, Themes.RED)
                }
            }
        }
    }
}

#Preview("Post Menu > Details") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    PostDetailsMenuSheet(nrPost: nrPost)
                }
            }
        }
    }
}

#Preview("Actual sheet") {
    PreviewContainer({ pe in
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let nrPost = PreviewFetcher.fetchNRPost() {
                PostMenuButton(nrPost: nrPost)
                    .withSheets()
            }
        }
    }
}
