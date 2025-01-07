//
//  ProfileRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ProfileCardByPubkey: View {
    public let pubkey: String
    public var theme: Theme = Themes.default.theme
    @StateObject private var vm = FetchVM<Contact>(timeout: 2.5, debounceTime: 0.05)
    @State var fixedPfp: URL?
    
    var body: some View {
        Group {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task { [weak vm] in
                        guard let vm else { return }
                        vm.setFetchParams((
                            prio: false,
                            req: { [weak vm] _ in
                                guard let vm else { return }
                                if let contact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().viewContext) { // 1. CHECK LOCAL DB
                                    vm.ready(contact)
                                }
                                else { // 2. ELSE CHECK RELAY
                                    req(RM.getUserMetadata(pubkey: pubkey))
                                }
                            },
                            onComplete: { [weak vm] relayMessage, _ in // TODO: Should make compatible with Contact also instead of just Event
                                DispatchQueue.main.async {
                                    guard let vm else { return }
                                    if let contact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().viewContext) { // 3. WE FOUND IT ON RELAY
                                        vm.ready(contact)
                                    }
                                    else { // 4. TIME OUT
                                        vm.timeout()
                                    }
                                }
                            },
                            altReq: nil
                            
                        ))
                        vm.fetch()
                    }
            case .ready(let contact):
                ProfileRow(contact: contact)
            case .timeout:
                Text("Unable to fetch profile")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
        )
        .clipped()
    }
}

struct ProfileRow: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var la: LoggedInAccount
    @ObservedObject private var fg: FollowingGuardian = .shared
     
    // Following/Unfollowing tap is slow so update UI and do in background:
    @State private var isFollowing = false
    public var withoutFollowButton = false
    public var tapEnabled: Bool = true
    public var showNpub: Bool = false
    @ObservedObject public var contact:Contact
    
    @State private var similarPFP = false
    @State private var similarToPubkey: String? = nil
    @State private var fixedPfp: URL?
    
    private var couldBeImposter: Bool {
        guard la.pubkey != contact.pubkey else { return false }
        guard !la.isFollowing(pubkey: contact.pubkey) else { return false }
        guard contact.couldBeImposter == -1 else { return contact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
                .overlay(alignment: .bottomTrailing) {
                    if let fixedPfp {
                        FixedPFP(picture: fixedPfp)
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(contact.anyName).font(.headline).foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if couldBeImposter {
                            PossibleImposterLabel(possibleImposterPubkey: contact.pubkey, followingPubkey: similarToPubkey ?? contact.similarToPubkey)
                            Text(contact.npub)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        else if contact.nip05veried, let nip05 = contact.nip05 {
                            NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                                .layoutPriority(3)
                        }
                        
                        if !couldBeImposter && showNpub {
                            Text(contact.npub)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        if let fixedName = contact.fixedName, fixedName != contact.anyName {
                            HStack {
                                Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "multiply.circle.fill")
                                    .onTapGesture {
                                        contact.fixedName = contact.anyName
                                    }
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                    if (!withoutFollowButton) {
                        Button {
                            guard isFullAccount() else { showReadOnlyMessage(); return }
                            if (isFollowing && !contact.isPrivateFollow) {
                                contact.isPrivateFollow = true
                                la.follow(contact, pubkey: contact.pubkey)
                            }
                            else if (isFollowing && contact.isPrivateFollow) {
                                isFollowing = false
                                contact.isPrivateFollow = false
                                la.unfollow(contact.pubkey)
                            }
                            else {
                                isFollowing = true
                                la.follow(contact, pubkey: contact.pubkey)
                            }
                        } label: {
                            FollowButton(isFollowing: isFollowing, isPrivateFollowing: contact.isPrivateFollow)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!fg.didReceiveContactListThisSession)
                    }
                }
                Text(contact.about ?? "").foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            guard tapEnabled else { return }
            navigateTo(ContactPath(key: contact.pubkey))
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            isFollowing = la.isFollowing(pubkey: contact.pubkey)
        }
        .onReceive(receiveNotification(.followersChanged)) { notification in
            guard let follows = notification.object as? Set<String> else { return }
            isFollowing = follows.contains(contact.pubkey)
        }
        .task { [weak contact] in
            guard let contact else { return }
            
            if let fixedPfp = contact.fixedPfp,
               fixedPfp != contact.picture,
               let fixedPfpUrl = URL(string: fixedPfp),
                hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl, size: 20.0))
            {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
            
            if la.isFollowing(pubkey: contact.pubkey) {
                isFollowing = true
            }
            else {
                guard !SettingsStore.shared.lowDataMode else { return }
                guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                guard contact.metadata_created_at != 0 else { return }
                guard contact.couldBeImposter == -1 else { return }
                guard contact.picture != nil, let cPic = contact.pictureUrl else { return }
                guard !NewOnboardingTracker.shared.isOnboarding else { return }
                guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }
                
                let contactAnyName = contact.anyName.lowercased()
                let cPubkey = contact.pubkey
                let currentAccountPubkey = la.pubkey
                
                bg().perform { [weak contact] in
                    guard la.pubkey == currentAccountPubkey else { return }
                    guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                        pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                    }) else { return }
                    
                    guard similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                    
                    L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarFollow.anyName)")
                    
                    Task.detached(priority: .background) {
                        let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                        if similarPFP {
                            L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                        }
                        
                        DispatchQueue.main.async {
                            guard let contact else { return }
                            guard currentAccountPubkey == la.pubkey else { return }
                            self.similarPFP = similarPFP
                            self.similarToPubkey = followingPubkey
                            contact.couldBeImposter = similarPFP ? 1 : 0
                            contact.similarToPubkey = similarPFP ? followingPubkey : nil
                            save()
                        }
                    }
                }
            }
            
            if let fixedPfp = contact.fixedPfp,
                fixedPfp != contact.picture,
               let fixedPfpUrl = URL(string: fixedPfp) {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
        }
    }
}

struct ProfileRow_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            ScrollView {
    //            let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
                
                if let contact = PreviewFetcher.fetchContact() {
                    
                    LazyVStack {
                        ProfileRow(contact: contact)
                        
                        ProfileRow(contact: contact)
                        
                        ProfileRow(contact: contact)
                        
                        Spacer()
                    }
                }
            }
        }
    }
}
