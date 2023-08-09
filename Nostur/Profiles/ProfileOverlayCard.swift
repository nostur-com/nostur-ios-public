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
    @State var contact:Contact? = nil
    var zapEtag:String? = nil // so other clients can still tally zaps
    
    @State private var backlog = Backlog(timeout: 15, auto: true)
    @State private var error:String? = nil
    
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
                        if let contact = Contact.fetchByPubkey(pubkey, context: viewContext) {
                            self.contact = contact
                        }
                        else {
                            let reqTask = ReqTask(
                                prefix: "CONTACT-",
                                reqCommand: { taskId in
                                    req(RM.getUserMetadata(pubkey: pubkey, subscriptionId: taskId))
                                },
                                processResponseCommand: { taskId, _ in
                                    if let contact = Contact.fetchByPubkey(pubkey, context: viewContext) {
                                        self.contact = contact
                                        self.backlog.clear()
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

struct ProfileOverlayCard: View {
    @ObservedObject var contact:Contact
    var zapEtag:String? // so other clients can still tally zaps
    @EnvironmentObject private var ns:NosturState
    @EnvironmentObject private var dim:DIMENSIONS
    @ObservedObject private var fg:FollowingGuardian = .shared
    private let sp:SocketPool = .shared
    
    // Following/Unfollowing tap is slow so update UI and do in background:
    @State private var isFollowing = false
    
    var withoutFollowButton = false
    
    @State var cancellationId:UUID? = nil
    @State var customZapId:UUID? = nil
    @State var activeColor = Self.grey
    @State var similarPFP = false
    @State var backlog = Backlog(timeout: 2.0, auto: true)
    @State var lastSeen:String? = nil
    
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
    
    var couldBeImposter:Bool {
        guard let account = NosturState.shared.account else { return false }
        guard account.publicKey != contact.pubkey else { return false }
        guard !NosturState.shared.isFollowing(contact) else { return false }
        guard contact.couldBeImposter == -1 else { return contact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                ZappablePFP(pubkey: contact.pubkey, contact: contact, size: DIMENSIONS.PFP_BIG, zapEtag: zapEtag)
                    .onTapGesture {
                        navigateTo(ContactPath(key: contact.pubkey))
                        sendNotification(.dismissMiniProfile)
                    }
                
                Spacer()
                
                if contact.anyLud {
                    ProfileZapButton(contact: contact, zapEtag: zapEtag)
                }
                
                if (!withoutFollowButton) {
                    Button {
                        if (isFollowing && !contact.privateFollow) {
                            contact.privateFollow = true
                            ns.follow(contact)
                        }
                        else if (isFollowing && contact.privateFollow) {
                            isFollowing = false
                            contact.privateFollow = false
                            ns.unfollow(contact)
                        }
                        else {
                            isFollowing = true
                            ns.follow(contact)
                        }
                    } label: {
                        FollowButton(isFollowing:isFollowing, isPrivateFollowing:contact.privateFollow)
                    }
                    .disabled(!fg.didReceiveContactListThisSession)
                }
            }
            
            VStack(alignment: .leading) {
                HStack(spacing:3) {
                    Text(contact.anyName).font(.title).foregroundColor(.primary)
                        .lineLimit(1)
                    if couldBeImposter {
                        Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                            .padding(.horizontal, 8)
                            .background(.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .layoutPriority(2)
                    }
                    else if (contact.nip05veried) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title)
                            .foregroundColor(Color("AccentColor"))
                    }
                    
                    if (NosturState.shared.followsYou(contact)) {
                        Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary)
                            .opacity(0.7)
                            .cornerRadius(13)
                    }
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
                
                Text(verbatim:lastSeen ?? "Last seen:")
                    .font(.caption).foregroundColor(.primary)
                        .lineLimit(1)
                    .opacity(lastSeen != nil ? 1.0 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
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
                    navigateTo(ContactPath(key: contact.pubkey, tab:"Posts"))
                    sendNotification(.dismissMiniProfile)
                }
                Spacer()
                Button(String(localized:"Following", comment:"Tab title")) {
                    navigateTo(ContactPath(key: contact.pubkey, tab:"Following"))
                    sendNotification(.dismissMiniProfile)
                }
                Spacer()
                Button(String(localized:"Media", comment:"Tab title")) {
                    navigateTo(ContactPath(key: contact.pubkey, tab:"Media"))
                    sendNotification(.dismissMiniProfile)
                }
                Spacer()
                Button(String(localized:"Likes", comment:"Tab title")) {
                    navigateTo(ContactPath(key: contact.pubkey, tab:"Likes"))
                    sendNotification(.dismissMiniProfile)
                }
                Spacer()
                Button(String(localized:"Zaps", comment:"Tab title")) {
                    navigateTo(ContactPath(key: contact.pubkey, tab:"Zaps"))
                    sendNotification(.dismissMiniProfile)
                }
            }
            .padding(.top, 10)
            .background(Color.systemBackground)
        }
        .background(Color.systemBackground)
        .padding(20)
        .roundedBoxShadow()
        .padding(10)
        .task {
            if (ns.isFollowing(contact)) {
                isFollowing = true
            }
            else {
                guard contact.couldBeImposter == -1 else { return }
                guard let account = NosturState.shared.account else { return }
                guard let similarContact = account.follows_.first(where: {
                    isSimilar(string1: $0.anyName.lowercased(), string2: contact.anyName.lowercased())
                }) else { return }
                guard let cPic = contact.picture, let wotPic = similarContact.picture else { return }
                similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                contact.couldBeImposter = similarPFP ? 1 : 0
            }
        }
        .task {
            if (NIP05Verifier.shouldVerify(contact)) {
                NIP05Verifier.shared.verify(contact)
            }
        }
        .task {
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
        .onChange(of: contact.nip05) { nip05 in
            if (NIP05Verifier.shouldVerify(contact)) {
                NIP05Verifier.shared.verify(contact)
            }
        }
        .task {
            EventRelationsQueue.shared.addAwaitingContact(contact)
            req(RM.getUserProfileKinds(pubkey: contact.pubkey, kinds: [0]))
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
            contact.zapState = .none
        }
    }
}

struct ProfileOverlayCard_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadContacts() }) {
            if let contact = PreviewFetcher.fetchContact() {
                ProfileOverlayCard(contact: contact)
            }
        }
        .background(Color.red)
    }
}
