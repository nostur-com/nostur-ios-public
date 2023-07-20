//
//  ProfileRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ProfileCardByPubkey: View {
    let pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
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
    @EnvironmentObject var ns:NosturState
    @ObservedObject var fg:FollowingGuardian = .shared
    let sp:SocketPool = .shared
     
    // Following/Unfollowing tap is slow so update UI and do in background:
    @State var isFollowing = false
    var withoutFollowButton = false
    @ObservedObject var contact:Contact
    
    @State var similarPFP = false
    
    var couldBeImposter:Bool {
        guard let account = NosturState.shared.account else { return false }
        guard account.publicKey != contact.pubkey else { return false }
        guard !ns.isFollowing(contact) else { return false }
        return similarPFP
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing:3) {
                            Text(contact.anyName).font(.headline).foregroundColor(.primary)
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
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))
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
                    }.multilineTextAlignment(.leading)
                    Spacer()
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
                Text(contact.about ?? "").foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(ContactPath(key: contact.pubkey))
        }
        .task {
            if (ns.isFollowing(contact)) {
                isFollowing = true
            }
            else {
                guard !ns.isFollowing(contact.pubkey) else { return }
                guard let account = ns.account else { return }
                guard let similarContact = account.follows_.first(where: {
                    $0.anyName == contact.anyName
                }) else { return }
                guard let cPic = contact.picture, let wotPic = similarContact.picture else { return }
                similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
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
