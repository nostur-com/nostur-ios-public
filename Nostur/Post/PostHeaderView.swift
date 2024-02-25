//
//  PostHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2024.
//

import SwiftUI

struct NRPostHeaderContainer: View {
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: NRPost.PFPAttributes
    @ObservedObject var settings: SettingsStore = .shared
    private var singleLine: Bool = true
    @State private var name: String

    init(nrPost: NRPost, singleLine: Bool = true) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.singleLine = singleLine
        self.name = nrPost.pfpAttributes.contact?.anyName ?? String(nrPost.pubkey.suffix(11))
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(name:  name, onTap: nameTapped, via: nrPost.via, createdAt: nrPost.createdAt, agoText: nrPost.ago, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine)
                .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                    guard profile.pubkey == nrPost.pubkey else { return }
                    withAnimation {
                        name = profile.name
                    }
                }
                .onAppear {
                    guard let nrContact = pfpAttributes.contact else {
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
                    guard let nrContact = pfpAttributes.contact else { return }
                    guard !SettingsStore.shared.lowDataMode else { return }
                    guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                    guard nrContact.metadata_created_at != 0 else { return }
                    guard nrContact.couldBeImposter == -1 else { return }
                    guard !nrContact.following else { return }
                    guard !NewOnboardingTracker.shared.isOnboarding else { return }

                    let contactAnyName = nrContact.anyName.lowercased()
                    let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                    let cPubkey = nrContact.pubkey

                    bg().perform { [weak nrContact] in
                        guard let nrContact else { return }
                        guard let account = account() else { return }
                        guard account.publicKey == currentAccountPubkey else { return }
                        guard let similarContact = account.follows.first(where: {
                            $0.pubkey != cPubkey && isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName) // TODO: follows.anyName cache could help, put in same followsPFP dict?
                        }) else { return }
                        guard let cPic = nrContact.pictureUrl, similarContact.picture != nil, let wotPic = similarContact.pictureUrl else { return }
                        Task.detached(priority: .background) {
                            let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                            DispatchQueue.main.async { [weak nrContact] in
                                guard let nrContact else { return }
                                guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                                nrContact.couldBeImposter = similarPFP ? 1 : 0
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
                    guard let nrContact = pfpAttributes.contact else {
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
    private let event: Event
    @ObservedObject var settings: SettingsStore = .shared
    private var singleLine: Bool = true
    @State private var name: String

    init(event: Event, singleLine: Bool = true) {
        self.event = event
        self.singleLine = singleLine
        self.name = event.contact?.anyName ?? String(event.pubkey.suffix(11))
    }

    var body: some View {
        VStack(alignment: .leading) { // Name + menu "replying to"
            PostHeaderView(name: name, onTap: nameTapped, via: event.via, createdAt: Date(timeIntervalSince1970: TimeInterval(event.created_at)), displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: singleLine)
                .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                    guard profile.pubkey == event.pubkey else { return }
                    withAnimation {
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
                        bg().perform {
                            guard let bgContact = event.contact?.bgContact() else { return }
                            EventRelationsQueue.shared.addAwaitingContact(bgContact, debugInfo: "EventHeaderContainer.002")
                            QueuedFetcher.shared.enqueue(pTag: pubkey)
                        }
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

                    let contactAnyName = contact.anyName.lowercased()
                    let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                    let cPubkey = contact.pubkey

                    bg().perform { [weak contact] in
                        guard let contact else { return }
                        guard let account = account() else { return }
                        guard account.publicKey == currentAccountPubkey else { return }
                        guard let similarContact = account.follows.first(where: {
                            $0.pubkey != cPubkey && isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName) // TODO: follows.anyName cache could help, put in same followsPFP dict?
                        }) else { return }
                        guard let cPic = contact.pictureUrl, similarContact.picture != nil, let wotPic = similarContact.pictureUrl else { return }
                        Task.detached(priority: .background) {
                            let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                            DispatchQueue.main.async { [weak contact] in
                                guard let contact else { return }
                                guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                                contact.couldBeImposter = similarPFP ? 1 : 0
                                bg().perform {
                                    guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                                    contact.couldBeImposter = similarPFP ? 1 : 0
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
    public let couldBeImposter: Int = -1
    public var via: String? = nil
    public let createdAt: Date
    public var agoText: String? = nil
    public let displayUserAgentEnabled: Bool
    public let singleLine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Group {
                Text(name)
                    .animation(.easeIn, value: name)
                    .foregroundColor(.primary)
                    .fontWeightBold()
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture { onTap?() }

                if couldBeImposter == 1 {
                    Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                        .padding(.horizontal, 8)
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top, 3)
                        .layoutPriority(2)
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
