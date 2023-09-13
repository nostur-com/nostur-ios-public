//
//  ProfileOverlayCard.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/07/2023.
//

import SwiftUI
import Combine

struct ProfileOverlayCardContainer: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    let pubkey:String
    @State var contact:NRContact? = nil
    var zapEtag:String? = nil // so other clients can still tally zaps
    
    @State private var backlog = Backlog(timeout: 15, auto: true)
    @State private var error: String? = nil
    
    var body: some View {
        VStack {
            if let error  {
                Text(error)
            }
            else if let contact {
                ProfileOverlayCard(contact: contact, zapEtag: zapEtag)
            }
            else {
                ProgressView()
                    .onAppear {
                        DataProvider.shared().bg.perform {
                            if let bgContact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().bg) {
                                let isFollowing = NosturState.shared.bgFollowingPublicKeys.contains(pubkey)
                                let nrContact = NRContact(contact: bgContact, following: isFollowing)
                                DispatchQueue.main.async {
                                    self.contact = nrContact
                                }
                            }
                            else {
                                let reqTask = ReqTask(
                                    prefix: "CONTACT-",
                                    reqCommand: { taskId in
                                        req(RM.getUserMetadata(pubkey: pubkey, subscriptionId: taskId))
                                    },
                                    processResponseCommand: { taskId, _ in
                                        DataProvider.shared().bg.perform {
                                            if let bgContact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().bg) {
                                                let isFollowing = NosturState.shared.bgFollowingPublicKeys.contains(pubkey)
                                                let nrContact = NRContact(contact: bgContact, following: isFollowing)
                                                DispatchQueue.main.async {
                                                    self.contact = nrContact
                                                }
                                                self.backlog.clear()
                                            }
                                        }
                                    },
                                    timeoutCommand: { taskId in
                                        DispatchQueue.main.async {
                                            self.error = "Could not fetch contact info"
                                        }
                                    })
                                
                                backlog.add(reqTask)
                                reqTask.fetch()
                            }
                        }
                    }
            }
        }
    }
}

struct ProfileOverlayCard: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme:Theme
    @ObservedObject var contact:NRContact
    var zapEtag:String? // so other clients can still tally zaps
    @EnvironmentObject private var ns:NosturState
    @EnvironmentObject private var dim:DIMENSIONS
    @ObservedObject private var fg:FollowingGuardian = .shared
    private let sp:SocketPool = .shared
    
    var withoutFollowButton = false
    @State var similarPFP = false
    @State var backlog = Backlog(timeout: 5.0, auto: true)
    @State var lastSeen:String? = nil
    @State var isFollowingYou = false
    
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
    
    var couldBeImposter:Bool {
        guard let account = NosturState.shared.account else { return false }
        guard account.publicKey != contact.pubkey else { return false }
        guard !contact.following else { return false }
        guard contact.couldBeImposter == -1 else { return contact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        Box {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    ZappablePFP(pubkey: contact.pubkey, contact: contact, size: DIMENSIONS.PFP_BIG, zapEtag: zapEtag)
                        .onTapGesture {
                            dismiss()
                            navigateTo(ContactPath(key: contact.pubkey))
                            sendNotification(.dismissMiniProfile)
                        }
                    
                    Spacer()
                    
                    if contact.anyLud {
                        ProfileZapButton(contact: contact, zapEtag: zapEtag)
                    }
                    
                    VStack {
                        if (!withoutFollowButton) {
                            Button {
                                if (contact.following && !contact.privateFollow) {
                                    contact.follow(privateFollow: true)
                                }
                                else if (contact.following && contact.privateFollow) {
                                    contact.unfollow()
                                }
                                else {
                                    contact.follow()
                                }
                            } label: {
                                FollowButton(isFollowing:contact.following, isPrivateFollowing:contact.privateFollow)
                            }
                            .disabled(!fg.didReceiveContactListThisSession)
                        }
                        Button("Show feed") {
                            guard let account = ns.account else { return }
                            LVMManager.shared.followingLVM(forAccount: account)
                                .loadSomeonesFeed(contact.pubkey)
                            sendNotification(.showingSomeoneElsesFeed, contact)
                            sendNotification(.dismissMiniProfile)
                        }
                        .buttonStyle(NosturButton())
                    }
                }
                
                VStack(alignment: .leading) {
                    HStack(alignment: .bottom, spacing: 3) {
                        Text(contact.anyName).font(.title).foregroundColor(.primary)
                            .lineLimit(1)
                        if let nip05 = contact.nip05, contact.nip05verified, contact.nip05nameOnly.lowercased() == contact.anyName.lowercased() {
                            NostrAddress(nip05: nip05, shortened: true)
                                .layoutPriority(3)
                                .offset(y: -4)
                        }
                        if (isFollowingYou) {
                            Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary)
                                .opacity(0.7)
                                .cornerRadius(13)
                                .offset(y: -4)
                        }
                    }
                    
                    if couldBeImposter {
                        Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                            .padding(.horizontal, 8)
                            .background(.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .layoutPriority(2)
                    }
                    else if let nip05 = contact.nip05, contact.nip05verified, contact.nip05nameOnly.lowercased() != contact.anyName.lowercased() {
                        NostrAddress(nip05: nip05, shortened: false)
                            .layoutPriority(3)
                    }

                    if let fixedName = contact.fixedName, fixedName != contact.anyName {
                        HStack {
                            Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                .lineLimit(1)
                            Image(systemName: "multiply.circle.fill")
                                .onTapGesture {
                                    contact.setFixedName(contact.anyName)
                                }
                        }
                    }
                    
                    Text(verbatim:lastSeen ?? "Last seen:")
                        .font(.caption).foregroundColor(.primary)
                            .lineLimit(1)
                        .opacity(lastSeen != nil ? 1.0 : 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                    navigateTo(ContactPath(key: contact.pubkey))
                    sendNotification(.dismissMiniProfile)
                }
                .padding(.bottom, 10)
                
                Text(contact.about ?? "")
                    .lineLimit(15)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing:0) {
                    Button(String(localized:"Posts", comment:"Tab title")) {
                        dismiss()
                        navigateTo(ContactPath(key: contact.pubkey, tab:"Posts"))
                        sendNotification(.dismissMiniProfile)
                    }
                    Spacer()
                    Button(String(localized:"Following", comment:"Tab title")) {
                        dismiss()
                        navigateTo(ContactPath(key: contact.pubkey, tab:"Following"))
                        sendNotification(.dismissMiniProfile)
                    }
                    Spacer()
                    Button(String(localized:"Media", comment:"Tab title")) {
                        dismiss()
                        navigateTo(ContactPath(key: contact.pubkey, tab:"Media"))
                        sendNotification(.dismissMiniProfile)
                    }
                    Spacer()
                    Button(String(localized:"Likes", comment:"Tab title")) {
                        dismiss()
                        navigateTo(ContactPath(key: contact.pubkey, tab:"Likes"))
                        sendNotification(.dismissMiniProfile)
                    }
                    Spacer()
                    Button(String(localized:"Zaps", comment:"Tab title")) {
                        dismiss()
                        navigateTo(ContactPath(key: contact.pubkey, tab:"Zaps"))
                        sendNotification(.dismissMiniProfile)
                    }
                }
                .padding(.top, 10)
                .background(theme.background)
            }
        }
        .padding(10)
        .background {
            theme.background
                .shadow(color: Color("ShadowColor").opacity(0.25), radius: 5)
        }
        .task {
            guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
            guard !contact.following else { return }
            guard contact.metadata_created_at != 0 else { return }
            guard contact.couldBeImposter == -1 else { return }
            guard let cPic = contact.pictureUrl else { return }
            guard !NewOnboardingTracker.shared.isOnboarding else { return }
            
            let contactAnyName = contact.anyName.lowercased()
            let cPubkey = contact.pubkey
            let currentAccountPubkey = NosturState.shared.activeAccountPublicKey
            
            DataProvider.shared().bg.perform {
                guard let account = NosturState.shared.bgAccount else { return }
                guard account.publicKey == currentAccountPubkey else { return }
                guard let similarContact = account.follows_.first(where: {
                    isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName)
                }) else { return }
                guard let wotPic = similarContact.picture else { return }
                
                L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarContact.anyName)")
                
                Task.detached(priority: .background) {
                    let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                    if similarPFP {
                        L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                    }
                    
                    DispatchQueue.main.async {
                        guard currentAccountPubkey == NosturState.shared.activeAccountPublicKey else { return }
                        self.similarPFP = similarPFP
                        contact.couldBeImposter = similarPFP ? 1 : 0
                    }
                }
            }
        }
        .task {
            let contact = contact.mainContact
            EventRelationsQueue.shared.addAwaitingContact(contact)
            if (ns.followsYou(contact)) {
                isFollowingYou = true
            }
            
            let task = ReqTask(
                reqCommand: { (taskId) in
                    req(RM.getUserProfileKinds(pubkey: contact.pubkey, subscriptionId: taskId, kinds: [0,3]))
                },
                processResponseCommand: { (taskId, _) in
                    if (ns.followsYou(contact)) {
                        isFollowingYou = true
                    }
                },
                timeoutCommand: { taskId in
                    if (ns.followsYou(contact)) {
                        isFollowingYou = true
                    }
                })

            backlog.add(task)
            task.fetch()
            
            
            if (NIP05Verifier.shouldVerify(contact)) {
                NIP05Verifier.shared.verify(contact)
            }
            guard contact.anyLud else { return }
            do {
                if let lud16 = contact.lud16, lud16 != "" {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                        }
                    }
                }
                else if let lud06 = contact.lud06, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                        }
                    }
                }
            }
            catch {
                L.og.error("problem in lnurlp \(error)")
            }
        }
        .onChange(of: contact.mainContact.nip05) { nip05 in
            if (NIP05Verifier.shouldVerify(contact.mainContact)) {
                NIP05Verifier.shared.verify(contact.mainContact)
            }
        }
        .task {
            let contactPubkey = contact.pubkey
            let reqTask = ReqTask(prefix: "SEEN-", reqCommand: { taskId in
                req(RM.getLastSeen(pubkey: contactPubkey, subscriptionId: taskId))
            }, processResponseCommand: { taskId, _ in
                DataProvider.shared().bg.perform {
                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: DataProvider.shared().bg) {
                        let agoString = last.date.agoString
                        DispatchQueue.main.async {
                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                        }
                    }
                }
            }, timeoutCommand: { taskId in
                DataProvider.shared().bg.perform {
                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: DataProvider.shared().bg) {
                        let agoString = last.date.agoString
                        DispatchQueue.main.async {
                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                        }
                    }
                }
            })
            
            backlog.add(reqTask)
            reqTask.fetch()
        }
        .onDisappear {
            DataProvider.shared().bg.perform {
                contact.contact.zapState = .none
            }
        }
    }
}

struct ProfileOverlayCard_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadContacts() }) {
            if let contact = PreviewFetcher.fetchNRContact() {
                ProfileOverlayCard(contact: contact)
            }
        }
        .background(Color.red)
    }
}
