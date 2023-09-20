//
//  ProfileRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ProfileCardByPubkey: View {
    public let pubkey:String
    
    @FetchRequest
    private var contacts:FetchedResults<Contact>
    
    init(pubkey:String) {
        self.pubkey = pubkey
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        if let contact = contacts.first {
            ProfileRow(contact: contact)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.regularMaterial, lineWidth: 1)
                )
        }
        else {
            ProgressView().onAppear {
                L.og.info("🟢 ProfileByPubkey.onAppear no contact so REQ.0: \(pubkey)")
                req(RM.getUserMetadata(pubkey: pubkey))
            }
        }
    }
}

struct ProfileRow: View {
    @EnvironmentObject private var theme:Theme
    @EnvironmentObject private var la:LoggedInAccount
    @ObservedObject private var fg:FollowingGuardian = .shared
     
    // Following/Unfollowing tap is slow so update UI and do in background:
    @State private var isFollowing = false
    public var withoutFollowButton = false
    @ObservedObject public var contact:Contact
    
    @State private var similarPFP = false
    
    private var couldBeImposter:Bool {
        guard la.pubkey != contact.pubkey else { return false }
        guard !la.isFollowing(pubkey: contact.pubkey) else { return false }
        guard contact.couldBeImposter == -1 else { return contact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(contact.anyName).font(.headline).foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if couldBeImposter {
                            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                .padding(.horizontal, 8)
                                .background(.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.top, 3)
                                .layoutPriority(2)
                        }
                        else if contact.nip05veried, let nip05 = contact.nip05 {
                            NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                                .layoutPriority(3)
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
                            if (isFollowing && !contact.privateFollow) {
                                contact.privateFollow = true
                                la.follow(contact, pubkey: contact.pubkey)
                            }
                            else if (isFollowing && contact.privateFollow) {
                                isFollowing = false
                                contact.privateFollow = false
                                la.unfollow(contact, pubkey: contact.pubkey)
                            }
                            else {
                                isFollowing = true
                                la.follow(contact, pubkey: contact.pubkey)
                            }
                        } label: {
                            FollowButton(isFollowing:isFollowing, isPrivateFollowing:contact.privateFollow)
                        }
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
            navigateTo(ContactPath(key: contact.pubkey))
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            isFollowing = la.isFollowing(pubkey: contact.pubkey)
        }
        .task {
            if la.isFollowing(pubkey: contact.pubkey) {
                isFollowing = true
            }
            else {
                guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                guard contact.metadata_created_at != 0 else { return }
                guard contact.couldBeImposter == -1 else { return }
                guard let cPic = contact.picture else { return }
                guard !NewOnboardingTracker.shared.isOnboarding else { return }
                
                let contactAnyName = contact.anyName.lowercased()
                let cPubkey = contact.pubkey
                let currentAccountPubkey = la.pubkey
                
                DataProvider.shared().bg.perform {
                    guard let account = la.bgAccount else { return }
                    guard account.publicKey == currentAccountPubkey else { return }
                    guard let similarContact = account.follows_.first(where: {
                        $0.pubkey != cPubkey && isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName)
                    }) else { return }
                    guard let wotPic = similarContact.picture else { return }
                    
                    L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarContact.anyName)")
                    
                    Task.detached(priority: .background) {
                        let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                        if similarPFP {
                            L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                        }
                        
                        DispatchQueue.main.async {
                            guard currentAccountPubkey == la.pubkey else { return }
                            self.similarPFP = similarPFP
                            contact.couldBeImposter = similarPFP ? 1 : 0
                        }
                    }
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
