//
//  PostHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2024.
//

import SwiftUI

struct NRPostHeaderContainer: View {
    private let nrPost: NRPost
    @ObservedObject var settings: SettingsStore = .shared
    @ObservedObject var pfpAttributes: PFPAttributes
    private var singleLine: Bool = true
    @State private var couldBeImposter: Int16

    init(nrPost: NRPost, singleLine: Bool = true) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.singleLine = singleLine
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(pubkey: nrPost.pubkey, name: pfpAttributes.anyName, onTap: nameTapped, couldBeImposter: couldBeImposter, similarToPubkey: nrPost.contact?.similarToPubkey , via: nrPost.via, createdAt: nrPost.createdAt, agoText: nrPost.ago, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine, restricted: nrPost.isRestricted)
                .onAppear {
                    guard let nrContact = nrPost.contact else {
                        bg().perform {
                           EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NRPostHeaderContainer.001")
                           QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                        return
                    }
                    if nrContact.metadata_created_at == 0 {
                        guard let bgContact = nrContact.contact else { return }
                        EventRelationsQueue.shared.addAwaitingContact(bgContact, debugInfo: "NRPostHeaderContainer.002")
                        QueuedFetcher.shared.enqueue(pTag: nrContact.pubkey)
                    }
                }
                .task {
                    guard let nrContact = nrPost.contact else { return }
                    guard !SettingsStore.shared.lowDataMode else { return }
                    guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                    guard nrContact.metadata_created_at != 0 else { return }
                    guard nrContact.couldBeImposter == -1 else { return }
                    
                    guard let la = NRState.shared.loggedInAccount else { return }
                    guard la.account.publicKey != nrContact.pubkey else { return }
                    guard !la.isFollowing(pubkey: nrContact.pubkey) else { return }
                    
                    guard !NewOnboardingTracker.shared.isOnboarding else { return }
                    guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }

                    let contactAnyName = nrContact.anyName.lowercased()
                    let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                    let cPubkey = nrContact.pubkey

                    bg().perform { [weak nrContact] in
                        guard let nrContact else { return }
                        guard let account = account() else { return }
                        guard account.publicKey == currentAccountPubkey else { return }
                        guard let (_, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                            pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                        }) else { return }
                        
                        guard let cPic = nrContact.pictureUrl, similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                        Task.detached(priority: .background) {
                            let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                            DispatchQueue.main.async { [weak nrContact] in
                                guard let nrContact else { return }
                                guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                                couldBeImposter = similarPFP ? 1 : 0
                                nrContact.couldBeImposter = couldBeImposter
                                bg().perform {
                                    guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                                    nrContact.contact?.couldBeImposter = similarPFP ? 1 : 0
        //                            DataProvider.shared().bgSave()
                                }
                            }
                        }
                    }
                }
                .onDisappear {
                    guard let nrContact = nrPost.contact else {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                        return
                    }
                    if nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.dequeue(pTag: nrContact.pubkey)
                    }
                }
        }
    }
    
    private func nameTapped() {
        guard let contact = nrPost.contact else { return }
        navigateTo(contact)
    }
}

struct EventHeaderContainer: View {
    private let event: Event // Main context
    @ObservedObject var settings: SettingsStore = .shared
    private var singleLine: Bool = true
    @State private var name: String
    @State private var couldBeImposter: Int16
    @State private var similarToPubkey: String? = nil

    init(event: Event, singleLine: Bool = true) {
        self.event = event
        self.singleLine = singleLine
        self.name = event.contact?.anyName ?? String(event.pubkey.suffix(11))
        self.couldBeImposter = event.contact?.couldBeImposter ?? -1
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(pubkey: event.pubkey, name: name, onTap: nameTapped, couldBeImposter: couldBeImposter, similarToPubkey: similarToPubkey, via: event.via, createdAt: Date(timeIntervalSince1970: TimeInterval(event.created_at)), displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine, restricted: event.isRestricted)
                .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                    guard profile.pubkey == event.pubkey, name != profile.name else { return }
                    withAnimation(.easeIn) {
                        name = profile.name
                    }
                }
                .onAppear {
                    let pubkey = event.pubkey
                    guard let contact = event.contact else {
                        bg().perform { // TODO: event is from main context, should move away from that
                            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "EventHeaderContainer.001")
                            QueuedFetcher.shared.enqueue(pTag: pubkey)
                        }
                        return
                    }
                    if contact.metadata_created_at == 0 {
                        EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "EventHeaderContainer.002")
                        QueuedFetcher.shared.enqueue(pTag: pubkey)
                    }
                }
                .task {
                    guard let contact = event.contact else { return }
                    guard !SettingsStore.shared.lowDataMode else { return }
                    guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                    guard contact.metadata_created_at != 0 else { return }
                    guard contact.couldBeImposter == -1 else { return }
                    guard !isFollowing(contact.pubkey) else { return }
                    guard !NewOnboardingTracker.shared.isOnboarding else { return }
                    guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }

                    let contactAnyName = contact.anyName.lowercased()
                    let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                    let cPubkey = contact.pubkey

                    bg().perform { [weak contact] in
                        guard let contact, let bgContact = bg().object(with: contact.objectID) as? Contact else { return }
                        guard let account = account() else { return }
                        guard account.publicKey == currentAccountPubkey else { return }
                        guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                            pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                        }) else { return }
                        
                        guard let cPic = bgContact.pictureUrl, similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                        Task.detached(priority: .background) {
                            let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                            DispatchQueue.main.async { [weak contact] in
                                guard let contact else { return }
                                guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                                contact.couldBeImposter = similarPFP ? 1 : 0
                                couldBeImposter = similarPFP ? 1 : 0
                                similarToPubkey = similarPFP ? followingPubkey : nil
                                bg().perform {
                                    guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                                    bgContact.couldBeImposter = similarPFP ? 1 : 0
                                    bgContact.similarToPubkey = similarPFP ? followingPubkey : nil
                                }
                            }
                        }
                    }
                }
                .onDisappear {
                    guard let contact = event.contact else {
                        QueuedFetcher.shared.dequeue(pTag: event.pubkey)
                        return
                    }
                    if contact.metadata_created_at == 0 {
                        QueuedFetcher.shared.dequeue(pTag: contact.pubkey)
                    }
                }
        }
    }
    
    private func nameTapped() {
        guard let contact = event.contact else { return }
        navigateTo(ContactPath(key: contact.pubkey, navigationTitle: contact.anyName))
    }
}

#Preview {
    PreviewContainer({ pe in
               pe.loadContacts()
               pe.loadPosts()
           }) {
               VStack {
//                   PreviewHeaderView(authorName: "Fabian", accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e")
                   if let p = PreviewFetcher.fetchNRPost("953dbf6a952f43f70dbb4d6432593ba5b7f149a786d1750e4aa4cef40522c0a0") {
                       NRPostHeaderContainer(nrPost: p)
                   }
               }
           }
}

struct PostHeaderView: View {
    public let pubkey: String
    public let name: String
    public var onTap: (() -> Void)? = nil
    public var couldBeImposter: Int16 = -1
    public var similarToPubkey: String? = nil
    public var via: String? = nil
    public let createdAt: Date
    public var agoText: String? = nil
    public let displayUserAgentEnabled: Bool
    public let singleLine: Bool
    public var restricted: Bool = false

    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        HStack(alignment: .center, spacing: 5) {
            Text(name)
                .foregroundColor(.primary)
                .fontWeightBold()
                .animation(.smooth, value: name)
                .lineLimit(1)
                .layoutPriority(2)
                .onTapGesture { onTap?() }
            
            if restricted {
                RestrictedLabel()
                    .infoText("The author has marked this post as restricted.\n\nA restricted post is intended to be sent only to specific relays and should not be rebroadcasted to other relays.")
            }

            if couldBeImposter == 1 {
                PossibleImposterLabel(possibleImposterPubkey: pubkey, followingPubkey: similarToPubkey)
            }

            if (singleLine) {
                Ago(createdAt, agoText: agoText)
                    .equatable()
                    .layoutPriority(2)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if displayUserAgentEnabled, let via = via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
            }
        }
        if (!singleLine) {
            HStack {
                Ago(createdAt, agoText: agoText)
                    .equatable()
                    .layoutPriority(2)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if displayUserAgentEnabled, let via = via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}


struct RestrictedLabel: View {
    @EnvironmentObject private var themes: Themes
    
    var body: some View {
        Text("restricted", comment: "Label shown on a restricted post").font(.system(size: 12.0))
            .padding(.horizontal, 8)
            .background(themes.theme.accent.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 3)
            .layoutPriority(2)
    }
}
