//
//  Kind30000.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2025.
//

import SwiftUI
import OrderedCollections

// Kind 30000: Follow sets: categorized groups of users a client may choose to check out in different circumstances
// Also kind: 39089
struct Kind30000: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var availableWidth: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return dim.listWidth - 20
        }
        
        return dim.availableNoteRowImageWidth()
    }
    
    private let title: String
    private var followPs: OrderedSet<String>
    
    @State private var followNRContacts: [String: NRContact] = [:]
    @State private var nrContactsToRender: [NRContact] = []
    @State private var didLoadFollowNRContacts = false
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.forceAutoload = forceAutoload
        let followingPubkeys = follows()
        self.followPs = OrderedSet(nrPost.fastTags.filter { $0.0 == "p" && isValidPubkey($0.1) }.map { $0.1 }
            .sorted(by: { followingPubkeys.contains($0) && !followingPubkeys.contains($1) }))
        self.title = (nrPost.eventTitle ?? nrPost.dTag) ?? "List"
    }
    
    var body: some View {
        if isEmbedded {
            self.embeddedView
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateTo(nrPost, context: dim.id)
                }
        }
        else {
            self.normalView
                .onAppear(perform: self.onAppear)
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    guard !isDetail else { return }
                    navigateTo(nrPost, context: dim.id)
                }
        }
    }
    
    private func onAppear() {
        bg().perform {
            let followPsToUse = !isDetail && !isEmbedded ? followPs.prefix(20) : followPs.prefix(2000) // For detail and embedded all (sanity limit at 2000), else just first 10 (row)
            let followNRContacts = followPsToUse.map { NRContact.instance(of: $0) }
            // create key value dictionary of followNRContacts in from of [String: NRContact] where key is NRContact.pubkey
            let followNRContactsDict = Dictionary(uniqueKeysWithValues: followNRContacts.map { ($0.pubkey, $0) })
            
            Task { @MainActor in
                self.followNRContacts = followNRContactsDict
                self.didLoadFollowNRContacts = true
                
                self.missingPs = Set(followNRContactsDict.prefix(3).map { $0.value }
                    .filter { $0.metadata_created_at == 0 }
                    .map { $0.pubkey })
                
                self.listNamesText = followNRContactsDict.prefix(3).map { $0.value.anyName }.joined(separator: ", ")
                
                guard !missingPs.isEmpty else { return }
                QueuedFetcher.shared.enqueue(pTags:  self.missingPs)
            }
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    @ViewBuilder
    private var normalView: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
//        PostEmbeddedLayout(nrPost: nrPost, authorAtBottom: true) {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: true, forceAutoload: forceAutoload, isItem: true) {
            
            if didLoadFollowNRContacts && isDetail { // Show full list
                // if more that 20 do 2 columns
                if followPs.count > 20 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        contactRows
                    }
//                    .background(theme.listBackground)
                }
                // If more than 20, do LazyVStack
                else if followPs.count > 10 {
                    LazyVStack(alignment: .leading) {
                        contactRows
                    }
//                    .background(theme.listBackground)
                }
                else {
                    contactRows
//                        .background(theme.listBackground)
                }
            }
            else if didLoadFollowNRContacts { // Row view, show 10 big PFPS (prio follows)
                overlappingPFPs
                    .frame(width: dim.articleRowImageWidth(), alignment: .leading)
//                    .background(theme.listBackground)
            }
            else {
                ProgressView()
                    .frame(height: 100)
            }
        } title: {
            HStack {
                Text(title).font(.title2)
                    .fontWeightBold()
                    .lineLimit(1)
                Spacer()
                Button("Show preview") {
                    let pubkeys = nrPost.fastTags.filter { $0.0 == "p" && isValidPubkey($0.1) }.map { $0.1 }
                    
                    // 1. NXColumnConfig
                    let config = NXColumnConfig(id: "FeedPreview", columnType: .pubkeysPreview(Set(pubkeys)), name: "Preview")
                    let feedPreviewSheetInfo = FeedPreviewInfo(config: config, nrPost: nrPost)
                    AppSheetsModel.shared.feedPreviewSheetInfo = feedPreviewSheetInfo
                }
                .buttonStyle(NosturButton(bgColor: theme.accent))
            }
//            .background(theme.listBackground)
        }
    }
        
    @State private var showMiniProfile = false
    
    private func load10pfps() {
        nrContactsToRender = followPs.prefix(10).indices.map { index in
            NRContact.instance(of: followPs[index])
        }
    }
    
    @State private var missingPs: Set<String> = []
    @State private var listNamesText: String = ""
    
    @ViewBuilder
    private var overlappingPFPs: some View {
        ZStack(alignment: .leading) {
            theme.listBackground
            ForEach(nrContactsToRender.indices, id: \.self) { index in
                ZStack(alignment: .leading) {
                    ObservedPFP(nrContact: nrContactsToRender[index], forceFlat: true)
                        .id(nrContactsToRender[index].pubkey)
                        .zIndex(-Double(index))
                }
                .offset(x:Double(0 + (30*index)))
            }
        }
        .drawingGroup(opaque: true)
        .onAppear {
            load10pfps()
        }
        
        if !followNRContacts.isEmpty {
            HStack {
                Text(listNamesText)
                    .layoutPriority(1)
                    .onReceive(ViewUpdates.shared.profileUpdates.receive(on: RunLoop.main)) { profileInfo in
                        if missingPs.contains(profileInfo.pubkey) {
                            missingPs.remove(profileInfo.pubkey)
                            withAnimation {
                                listNamesText = followNRContacts.prefix(3).map { $0.value.anyName }.joined(separator: ", ")
                            }
                        }
                    }
                if followPs.count > 3 {
                    Text("and \(followPs.count - 3) more")
                        .layoutPriority(2)
                }
            }
            .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, authorAtBottom: true) {
            HStack {
                Text(title)
                    .fontWeight(.bold)
                    .lineLimit(4)
                Spacer()
                Button("Feed preview") {
                    let pubkeys = nrPost.fastTags.filter { $0.0 == "p" && isValidPubkey($0.1) }.map { $0.1 }
                    
                    // 1. NXColumnConfig
                    let config = NXColumnConfig(id: "FeedPreview", columnType: .pubkeysPreview(Set(pubkeys)), name: "Preview")
                    let feedPreviewSheetInfo = FeedPreviewInfo(config: config, nrPost: nrPost)
                    AppSheetsModel.shared.feedPreviewSheetInfo = feedPreviewSheetInfo
                }
                .buttonStyle(NosturButton(bgColor: theme.accent))
                .layoutPriority(1)
            }
            
            if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                Image(systemName: "exclamationmark.triangle.fill")
            }
            
            if didLoadFollowNRContacts {
                // if more that 20 do 2 columns
                if followPs.count > 20 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        contactRows
                    }
                }
                // If more than 20, do LazyVStack
                else if followPs.count > 10 {
                    LazyVStack(alignment: .leading) {
                        contactRows
                    }
                }
                else {
                    contactRows
                }
            }
            else {
                ProgressView()
                    .frame(height: 100)
            }
    
        }
    }
    
    private func loadContactRows() {
        nrContactsToRender = followNRContacts.map({ pubkey, nrContact in
            nrContact
        })
        didLoad = true
    }
    
    @State private var didLoad = false
    
    // TODO: Should show people you follow first, at least in non-detail truncated view
    @ViewBuilder
    private var contactRows: some View {
        if didLoad {
            ForEach(nrContactsToRender) { nrContact in
                PubkeyRow(nrContact: nrContact)
                    .lineLimit(1)
                    .id(nrContact.pubkey)
                    .onAppear {
                        bg().perform {
                            if nrContact.metadata_created_at == 0 {
                                QueuedFetcher.shared.enqueue(pTag: nrContact.pubkey)
                            }
                        }
                    }
                    .onDisappear {
                        bg().perform {
                            if nrContact.metadata_created_at == 0 {
                                QueuedFetcher.shared.dequeue(pTag: nrContact.pubkey)
                            }
                        }
                    }
            }
            .background(theme.listBackground)
            .drawingGroup(opaque: true)
        }
        else {
            ProgressView()
                .onAppear {
                    loadContactRows()
                }
        }
    }
}


struct PubkeyRow: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject var nrContact: NRContact
    
    var body: some View {
        HStack {
            ObservedPFP(nrContact: nrContact, size: 20.0)
            Text(nrContact.anyName)
        }
        .onTapGesture {
            guard !nxViewingContext.contains(.preview) else { return }
            navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: dim.id)
        }
    }
}

#Preview("Sharing a list") {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT","sharing",{"tags":[["p","9ca0bd7450742d6a20319c0e3d4c679c9e046a9dc70e8ef55c2905e24052340b"],["client","noStrudel","31990:266815e0c9210dfa324c6cba3573b14bee49da4209a9456f9484e5106cd408a5:1686066542546"]],"sig":"069a80f42978c1c872d72ee26add0ad6e12875ae209838d432885123856a90810df1d1b3c18de716997e4530b1bba2b75973f39012be626a95be0589f9c38a6d","created_at":1743290622,"kind":1,"id":"294e9d025dfcc096ef52474fa9905537a7b0c9091af723b074a77f96c8c325e0","pubkey":"9ca0bd7450742d6a20319c0e3d4c679c9e046a9dc70e8ef55c2905e24052340b","content":"A growing list of those loveable rogues of nostr, The Curmudgeons\n\nnostr:naddr1qvzqqqr4xqpzp89qh469qapddgsrr8qw84xx08y7q34fm3cw3m64c2g9ufq9ydqtqy2hwumn8ghj7un9d3shjtnyv9kh2uewd9hj7qgwwaehxw309ahx7uewd3hkctcqz48k2k33xyuxzajyxp98s42ed9q4xc2xve5q3yzkzp"}]"###,
            ###"["EVENT","list",{"tags":[["d","OeZ118avD0JxUYiASaFfh"],["title","curmudgeons"],["p","0c405798e0e39caf54d2b211879ba1d6a965109b1389fa55da5bb20dd96ba5a0"],["p","52b4a076bcbbbdc3a1aefa3735816cf74993b1b8db202b01c883c58be7fad8bd"],["p","4c800257a588a82849d049817c2bdaad984b25a45ad9f6dad66e47d3b47e3b2f"],["p","80caa3337d33760ee355697260af0a038ae6a82e6d0b195c7db3c7d02eb394ee"],["p","c55476b5799dd1dd158aec8e1f319f1cdcef2768919670f1ed3e8f3e733a1732"],["p","fd208ee8c8f283780a9552896e4823cc9dc6bfd442063889577106940fd927c1"],["p","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]],"kind":30000,"pubkey":"9ca0bd7450742d6a20319c0e3d4c679c9e046a9dc70e8ef55c2905e24052340b","sig":"2c858e84623d36b81964eb10cd2ca02f38590e4e931c16f0c941e2734cfa1f0d38f3d2bcd09dcb504b4b33d07360c91d136caf217dd000976a75b39340b0eb36","id":"c4dab9d7ced0a943bc48a0c831e646085f2426ecbf68afc37f3ebe4abb87c89c","content":"","created_at":1743290706}]"###
        ])
        
    }) {
        if let kind1withNaddr = PreviewFetcher.fetchNRPost("294e9d025dfcc096ef52474fa9905537a7b0c9091af723b074a77f96c8c325e0") {
            Box {
                KindResolver(nrPost: kind1withNaddr)
            }
        }
    }
}

#Preview("Browse lists") {
    PreviewContainer({ pe in
        pe.parseMessages(dummyKind30000s)
    }) {
        let lists = Event.fetchEventsBy(kind: 30000, context: bg())
        let nrLists = lists.map { NRPost(event: $0) }
        ScrollView {
            LazyVStack {
                ForEach(nrLists) { nrList in
                    Box {
                        KindResolver(nrPost: nrList)
                    }
                }
            }
        }
    }
}
