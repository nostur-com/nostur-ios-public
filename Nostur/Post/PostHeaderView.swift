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
    private var singleLine: Bool = true
    @State private var name: String
    @State private var couldBeImposter: Int16

    init(nrPost: NRPost, singleLine: Bool = true) {
        self.nrPost = nrPost
        self.singleLine = singleLine
        self.name = nrPost.pfpAttributes.contact?.anyName ?? String(nrPost.pubkey.suffix(11))
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(name:  name, onTap: nameTapped, couldBeImposter: couldBeImposter, via: nrPost.via, createdAt: nrPost.createdAt, agoText: nrPost.ago, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine)
                .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                    guard profile.pubkey == nrPost.pubkey else { return }
                    withAnimation(.easeIn) {
                        name = profile.name
                    }
                    
                    // If post is on feed without kind-0 info, and then updated here,
                    // opening detail will still have old nrPost without updated name
                    // so update nrPost here
                    // Before this wasn't necessary because we were listening from nrPost
                    // now we are only listening on view, so update here
                    // Maybe we should check for update on loading detail instead....
                    nrPost.contact?.anyName = profile.name
                }
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
                    guard !nrContact.following else { return }
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

    init(event: Event, singleLine: Bool = true) {
        self.event = event
        self.singleLine = singleLine
        self.name = event.contact?.anyName ?? String(event.pubkey.suffix(11))
        self.couldBeImposter = event.contact?.couldBeImposter ?? -1
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(name: name, onTap: nameTapped, couldBeImposter: couldBeImposter, via: event.via, createdAt: Date(timeIntervalSince1970: TimeInterval(event.created_at)), displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine)
                .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                    guard profile.pubkey == event.pubkey else { return }
                    withAnimation(.easeIn) {
                        name = profile.name
                    }
                }
                .onAppear {
                    let pubkey = event.pubkey
                    guard let contact = event.contact else {
                        bg().perform {
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
                        guard let (_, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
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
                                bg().perform {
                                    guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                                    bgContact.couldBeImposter = similarPFP ? 1 : 0
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
    public let name: String
    public var onTap: (() -> Void)? = nil
    public var couldBeImposter: Int16 = -1
    public var via: String? = nil
    public let createdAt: Date
    public var agoText: String? = nil
    public let displayUserAgentEnabled: Bool
    public let singleLine: Bool

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        HStack(alignment: .center, spacing: 5) {
            Text(name)
                .foregroundColor(.primary)
                .fontWeightBold()
                .lineLimit(1)
                .layoutPriority(2)
                .onTapGesture { onTap?() }

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
