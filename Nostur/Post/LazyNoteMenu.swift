//
//  LazyNoteMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/05/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct LazyNoteMenuButton: View {
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

struct LazyNoteMenuSheet: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    public let nrPost: NRPost
    @Environment(\.dismiss) private var dismiss
    private let NEXT_SHEET_DELAY = 0.05
    @State private var followToggles = false
    @State private var blockOptions = false
    @State private var pubkeysInPost: Set<String> = []
    
    var body: some View {
        List {
            Group {
                HStack {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.shareWeblink, nrPost)
                        }
                    } label: {
                        Label(String(localized:"Share link", comment: "Post context menu button"), systemImage: "square.and.arrow.up")
                            .padding(.trailing, 5)
                    }
                    .buttonStyle(.plain)
                    if #available(iOS 16, *), nrPost.kind != 30023 {
                        Divider()
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                                sendNotification(.sharePostScreenshot, nrPost)
                            }
                        } label: {
                            Text("screenshot", comment:"Post context menu button")
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            Color.white
                                .opacity(0.01)
                                .scaleEffect(x: 1.75, y:1.7)
                        )
                        .onTapGesture {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                                sendNotification(.sharePostScreenshot, nrPost)
                            }
                        }
                    }
                }
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY + 0.35) { // Short delay freezes????
                        sendNotification(.addRemoveToListsheet, nrPost.contact)
                    }
                } label: {
                    Label(String(localized:"Add/Remove \(nrPost.anyName) from custom feed", comment: "Post context menu button"), systemImage: "person.2.crop.square.stack")
                }
                if pubkeysInPost.count > 1 {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY + 0.35) { // Short delay freezes????
                            AppSheetsModel.shared.addContactsToListInfo = AddContactsToListInfo(pubkeys: pubkeysInPost)
                        }
                    } label: {
                        Label(String(localized:"Add \(pubkeysInPost.count) contacts to custom feed", comment: "Post context menu button"), systemImage: "person.2.crop.square.stack")
                    }
                }
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
                    Label(String(localized:"Add private note", comment: "Post context menu button"), systemImage: "note.text")
                }
                HStack {
                    Button {
                        UIPasteboard.general.string = nrPost.plainText
                        dismiss()
                    } label: {
                        Label(String(localized:"Copy post text", comment: "Post context menu button"), systemImage: "doc.on.clipboard")
                            .padding(.trailing, 5)
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Button {
                        let relaysForHint: Set<String> = resolveRelayHint(forPubkey: nrPost.pubkey, receivedFromRelays: nrPost.footerAttributes.relays)
                        
                        if nrPost.kind >= 30000 && nrPost.kind < 40000 {
                            if let si = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(nrPost.kind), pubkey: nrPost.pubkey, dTag: nrPost.dTag, relays: Array(relaysForHint)) {
                                UIPasteboard.general.string = "nostr:\(si.identifier)"
                                dismiss()
                            }
                        }
                        else {
                            if let si = try? NostrEssentials.ShareableIdentifier("nevent", id: nrPost.id, kind: Int(nrPost.kind), pubkey: nrPost.pubkey, relays: Array(relaysForHint)) {
                                UIPasteboard.general.string = "nostr:\(si.identifier)"
                                dismiss()
                            }
                        }
                    } label: {
                        Text("ID", comment:"Label for post identifier (ID)")
                            .padding(.horizontal, 5)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        Color.white
                            .opacity(0.01)
                            .scaleEffect(x: 1.75, y:1.7)
                    )
                    .onTapGesture {
                        let relaysForHint: Set<String> = resolveRelayHint(forPubkey: nrPost.pubkey, receivedFromRelays: nrPost.footerAttributes.relays)
                        if nrPost.kind >= 30000 && nrPost.kind < 40000 {
                            if let si = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(nrPost.kind), pubkey: nrPost.pubkey, dTag: nrPost.dTag, relays: Array(relaysForHint)) {
                                UIPasteboard.general.string = "nostr:\(si.identifier)"
                                dismiss()
                            }
                        }
                        else {
                            if let si = try? NostrEssentials.ShareableIdentifier("nevent", id: nrPost.id, kind: Int(nrPost.kind), pubkey: nrPost.pubkey, relays: Array(relaysForHint)) {
                                UIPasteboard.general.string = "nostr:\(si.identifier)"
                                dismiss()
                            }
                        }
                    }
                    
                    Divider()
                    Button {
                        UIPasteboard.general.string = nrPost.id
                        dismiss()
                    } label: {
                        Text("hex", comment: "Short label for the word 'hexadecimal'")
                            .padding(.horizontal, 5)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        Color.white
                            .opacity(0.01)
                            .scaleEffect(x: 1.3, y:1.7)
                    )
                    .onTapGesture {
                        UIPasteboard.general.string = nrPost.id
                        dismiss()
                    }
                    Divider()
                    Button {
                        dismiss()
                        UIPasteboard.general.string = Event.fetchEvent(id: nrPost.id, context: viewContext())?.toNEvent().eventJson()
                    } label: {
                        Text("source", comment: "The word 'source' as in source code")
                            .padding(.horizontal, 5)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        Color.white
                            .opacity(0.01)
                            .scaleEffect(x: 1.35, y:1.7)
                    )
                    .onTapGesture {
                        dismiss()
                        UIPasteboard.general.string = Event.fetchEvent(id: nrPost.id, context: viewContext())?.toNEvent().eventJson()
                    }
                }
                Button {
                    dismiss()
                    sendNotification(.clearNavigation)
                    sendNotification(.showingSomeoneElsesFeed, nrPost.contact)
                    sendNotification(.dismissMiniProfile)
                } label: {
                    Label(String(localized:"Show \(nrPost.anyName)'s feed", comment: "Post context menu button to show someone's feed"), systemImage: "rectangle.stack.fill")
                }
                HStack {
                    Button {
                        guard isFullAccount() else {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)  {
                                showReadOnlyMessage()
                            }
                            return
                        }
                        dismiss()
                        la.follow(nrPost.pubkey)
                    } label: {
                        Label(String(localized:"Follow \(nrPost.anyName)", comment: "Post context menu button to Follow (name)"), systemImage: "person.fill")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Divider()
                    Button { followToggles = true } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .foregroundColor(theme.accent)
            .listRowBackground(theme.background)
            
            Group {
                HStack {
                    Button {
                        dismiss()
                        block(pubkey: nrPost.pubkey, name: nrPost.anyName)
                    } label: {
                        Label(String(localized:"Block \(nrPost.anyName)", comment: "Post context menu action to Block (name)"), systemImage: "slash.circle")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Divider()
                    Button { blockOptions = true } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                
                Button {
                    dismiss()
                    L.og.debug("Mute conversation")
                    mute(eventId: nrPost.id, replyToRootId: nrPost.replyToRootId, replyToId: nrPost.replyToId)
                } label: {
                    Label(String(localized:"Mute conversation", comment: "Post context menu action to mute conversation"), systemImage: "bell.slash.fill")
                }
                
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.reportPost, nrPost)
                    }
                } label: {
                    Label(String(localized:"Report.verb", comment:"Post context menu action to Report a post or user"), systemImage: "flag")
                }
            }
            .foregroundColor(theme.accent)
            .listRowBackground(theme.background)
            
            if (AccountsState.shared.activeAccountPublicKey == nrPost.pubkey) {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.requestDeletePost, nrPost.id)
                    }
                } label: {
                    Label(String(localized:"Delete", comment:"Post context menu action to Delete a post"), systemImage: "trash")
                }
                .foregroundColor(theme.accent)
                .listRowBackground(theme.background)
            }
            
            Button {
                dismiss()
                guard let mainEvent = Event.fetchEvent(id: nrPost.id, context: viewContext()) else { return }
                let nEvent = mainEvent.toNEvent()
                
                if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey && mainEvent.flags == "nsecbunker_unsigned" && la.account.isNC {
                    NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: la.account,  whenSigned: { signedEvent in
                        Unpublisher.shared.publishNow(signedEvent)
                    })
                }
                else {
                    Unpublisher.shared.publishNow(nEvent)
                }
            } label: {
                if nrPost.pubkey == AccountsState.shared.activeAccountPublicKey {
                    Label(String(localized:"Rebroadcast (again)", comment: "Button to broadcast own post again"), systemImage: "dot.radiowaves.left.and.right")
                }
                else {
                    Label(String(localized:"Rebroadcast", comment: "Button to rebroadcast a post"), systemImage: "dot.radiowaves.left.and.right")
                }
            }
            .foregroundColor(theme.accent)
            .listRowBackground(theme.background)
            
            if !nrPost.footerAttributes.relays.isEmpty {
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
                    ForEach(nrPost.footerAttributes.relays.sorted(by: <), id: \.self) { relay in
                        Text(String(relay)).lineLimit(1)
                    }
                }
                .foregroundColor(.gray)
                .listRowBackground(theme.background)
            }
        }
        .environment(\.theme, theme)
        .scrollContentBackgroundHidden()
        .listStyle(.plain)
        .background(theme.background)
        .navigationTitle(String(localized:"Post actions", comment:"Title of sheet showing actions to perform on post"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                
            }
        }
        .nbNavigationDestination(isPresented: $followToggles) {
            MultiFollowSheet(pubkey: nrPost.pubkey, name: nrPost.anyName, onDismiss: { dismiss() })
                .environment(\.theme, theme)
        }
        .nbNavigationDestination(isPresented: $blockOptions) {
            BlockOptions(pubkey: nrPost.pubkey, name: nrPost.anyName, onDismiss: { dismiss() })
                .environment(\.theme, theme)
        }
        .onAppear {
            let onlyPtags: [String] = nrPost.fastTags.compactMap({ fastTag in
                if (fastTag.0 != "p" || !isValidPubkey(fastTag.1)) { return nil }
                return fastTag.1
            })
            let pTagPubkeys: Set<String> = Set(onlyPtags).union([nrPost.pubkey])
            pubkeysInPost = pTagPubkeys
        }
    }
}

struct LazyNoteMenuSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadAccounts()
            pe.loadPosts()
        }) {
            NBNavigationStack {
                VStack {
                    if let nrPost = PreviewFetcher.fetchNRPost() {
                        LazyNoteMenuSheet(nrPost:nrPost)
                    }
                }
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let nrPost = PreviewFetcher.fetchNRPost() {
                LazyNoteMenuButton(nrPost:nrPost)
            }
        }
        .withSheets()
    }
}

struct BlockOptions: View {
    @Environment(\.theme) private var theme
    
    public let pubkey: String
    public let name: String
    public var onDismiss: (() -> Void)?

    var body: some View {
        Form {
            Section("Duration") {
                Button("Block for 1 hour") { temporaryBlock(pubkey: pubkey, forHours: 1, name: name); onDismiss?() }
                Button("Block for 4 hours") { temporaryBlock(pubkey: pubkey, forHours: 4, name: name); onDismiss?() }
                Button("Block for 8 hours") { temporaryBlock(pubkey: pubkey, forHours: 8, name: name); onDismiss?() }
                Button("Block for 1 day") { temporaryBlock(pubkey: pubkey, forHours: 24, name: name); onDismiss?() }
                Button("Block for 1 week") { temporaryBlock(pubkey: pubkey, forHours: 24*7, name: name); onDismiss?() }
                Button("Block for 1 month") { temporaryBlock(pubkey: pubkey, forHours: 24*31, name: name); onDismiss?() }
            }
        }
        .foregroundColor(theme.accent)
        .listRowBackground(theme.background)
        .navigationTitle("Block \(name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    onDismiss?()
                }
            }
        }
    }
}


struct PostMenu: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    public let nrPost: NRPost
    @Environment(\.dismiss) private var dismiss
    private let NEXT_SHEET_DELAY = 0.05
    @State private var followToggles = false
    @State private var blockOptions = false
    @State private var pubkeysInPost: Set<String> = []
    
    var body: some View {
        List {
            Button(role: .destructive, action: {
                // Navigate to sheet with id / link / screenshot 
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            // Delete button
            Button(role: .destructive, action: {
                
            }) {
                Label("Delete post", systemImage: "trash")
            }
            
            Button(action: {
                
            }) {
                Label("Pin to your profile", systemImage: "pin")
            }
            
            Button(action: {
                
            }) {
                Label("Add/remove from Highlights", systemImage: "star")
            }
        }
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
                }
            }
        }
    }
}

