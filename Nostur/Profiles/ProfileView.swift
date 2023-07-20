//
//  ProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2023.
//

import SwiftUI
import Nuke
import NukeUI

struct ProfileView: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject var settings:SettingsStore = .shared
    @ObservedObject var contact:Contact
    let pubkey:String
    var tab:String?
    
    @FetchRequest
    var relayEvents:FetchedResults<Event>
    
    @FetchRequest
    var kind0Events:FetchedResults<Event>
    
    @State var profilePicViewerIsShown = false
    @State var limit = 10
    @State var tabOffset = 0.0
    @State var selectedSubTab = "Posts"
    
    init(contact:Contact, tab:String? = nil) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.tab = tab
        
        
        let rl = Event.fetchRequest()
        rl.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        rl.predicate = NSPredicate(format: "pubkey == %@ AND kind == 10002", pubkey)
        _relayEvents = FetchRequest(fetchRequest: rl)
        
        let kind0 = Event.fetchRequest()
        kind0.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        kind0.predicate = NSPredicate(format: "pubkey == %@ AND kind == 0", pubkey)
        
        _kind0Events = FetchRequest(fetchRequest: kind0)
    }
    
    @State var similarPFP = false
    
    var couldBeImposter:Bool {
        guard let account = NosturState.shared.account else { return false }
        guard account.publicKey != contact.pubkey else { return false }
        guard !ns.isFollowing(contact) else { return false }
        return similarPFP
    }
    
    var body: some View {
        //        let _ = Self._printChanges()
        ScrollView {
            Color.clear.background( // GeometryReader in .background so it does not mess up layout
                GeometryReader { toolbarGEO in
                    Color.clear
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                VStack {
                                    HStack(spacing:2) {
                                        PFP(pubkey: contact.pubkey, contact: contact, size: 25)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color.systemBackground, lineWidth: 1)
                                            )
                                        Text("\(contact.authorName) ").font(.headline)
                                    }
                                    .offset(y: 160 + (max(-160,toolbarGEO.frame(in:.global).minY)))
                                }.frame(height: 40).clipped()
                            }
                            
                            ToolbarItem(placement: .navigationBarTrailing) {
                                VStack {
                                    ProfileFollowButton(contact: contact)
                                        .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                                }.frame(height: 40).clipped()
                                    .layoutPriority(2)
                            }
                        }
                }
            )
            
            LazyVStack(alignment:.leading, spacing:0, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack {
                        GeometryReader { geoBanner in
                            ProfileBanner(banner: contact.banner, width: dim.listWidth, offset: geoBanner.frame(in:.global).minY)
                                .overlay(alignment: .bottomLeading, content: {
                                    PFP(pubkey: contact.pubkey, contact: contact, size: DIMENSIONS.PFP_BIG)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.systemBackground, lineWidth: 3)
                                        )
                                        .onTapGesture {
                                            if (contact.picture != nil) {
                                                profilePicViewerIsShown = true
                                            }
                                        }
                                        .scaleEffect(min(1,max(0.5,geoBanner.frame(in:.global).minY / 70 + 1.3)), anchor:.bottom)
                                        .offset(x: 10, y: DIMENSIONS.PFP_BIG/2)
                                })
                            
                        }
                        
                        VStack(alignment: .leading) {
                            HStack(alignment:.top) {
                                if (!settings.hideBadges) {
                                    ProfileBadgesContainer(pubkey: contact.pubkey)
                                        .offset(x: 85, y: 0)
                                }
                                
                                Spacer()
                                
                                ProfileLightningButton(contact: contact)
                                
                                ProfileFollowButton(contact: contact)
                                    .padding(.trailing, 10)
                            }
                            .padding(.top, 10)
                            
                            HStack(spacing:0) {
                                Text("\(contact.anyName) ").font(.system(size: 24, weight:.bold))
                                if couldBeImposter {
                                    Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                        .padding(.horizontal, 8)
                                        .background(.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .layoutPriority(2)
                                }
                                else if (contact.nip05veried) {
                                    Group {
                                        Image(systemName: "checkmark.seal.fill")
                                        Text(contact.nip05domain).font(.footnote)
                                    }.foregroundColor(Color("AccentColor"))
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
                            
                            HStack {
                                //                                Text("@\(contact.username)").foregroundColor(.secondary)
                                ContactPrivateNoteToggle(contact: contact)
                                Menu {
                                    Button {
                                        UIPasteboard.general.string = contact.npub
                                    } label: {
                                        Label(String(localized:"Copy npub", comment:"Menu action"), systemImage: "doc.on.clipboard")
                                    }
                                    if let kind0 = kind0Events.first {
                                        Button {
                                            UIPasteboard.general.string = kind0.toNEvent().eventJson()
                                        } label: {
                                            Label(String(localized:"Copy profile source", comment:"Menu action"), systemImage: "doc.on.clipboard")
                                        }
                                    }
                                    
                                    Button {
                                        sendNotification(.addRemoveToListsheet, contact)
                                    } label: {
                                        Label(String(localized:"Add/Remove from lists", comment:"Menu action"), systemImage: "person.2.crop.square.stack")
                                    }
                                    
                                    
                                    Button {
                                        ns.objectWillChange.send()
                                        ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [contact.pubkey]
                                        sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
                                    } label: {
                                        Label(
                                            String(localized:"Block \(contact.anyName)", comment:"Menu action"), systemImage: "slash.circle")
                                    }
                                    Button {
                                        sendNotification(.reportContact, contact)
                                    } label: {
                                        Label(String(localized:"Report \(contact.anyName)", comment:"Menu action"), systemImage: "flag")
                                    }
                                    
                                    
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .fontWeight(.bold)
                                }
                                if (ns.followsYou(contact)) {
                                    Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary)
                                        .opacity(0.7)
                                        .cornerRadius(13)
                                }
                            }
                            
                            Text("\(String(contact.about ?? ""))\n")
                                .lineLimit(20)
                            
                            HStack(alignment: .center, spacing:0) {
                                if contact.followingPubkeys.isEmpty {
                                    ProgressView()
                                        .padding(.horizontal, 7)
                                }
                                else {
                                    Text("**\(contact.followingPubkeys.count)** ")
                                }
                                Text("Following  ", comment: "Label for Following count")
                                
                                Text("**♾️** Followers", comment: "Label for followers count")
                                    .onTapGesture {
                                        selectedSubTab = "Followers"
                                    }
                            }
                            .frame(height: 30)
                        }
                        .padding(10)
                        .padding(.top, 120)
                    }
                }
                ProfileTabs(contact: contact, selectedSubTab: $selectedSubTab)
            }
        }
        .background(Color.systemBackground)
        .preference(key: TabTitlePreferenceKey.self, value: contact.anyName)
        .onReceive(receiveNotification(.newFollowingListFromRelay)) { notification in
            let nEvent = notification.object as! NEvent
            if nEvent.publicKey == contact.pubkey {
                contact.objectWillChange.send()
            }
        }
        .onAppear {
            if let tab = tab {
                selectedSubTab = tab
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
            req(RM.getUserProfileKinds(pubkey: pubkey, kinds: [0,3,30008,10002]))
        }
        .fullScreenCover(isPresented: $profilePicViewerIsShown) {
            ProfilePicFullScreenSheet(profilePicViewerIsShown: $profilePicViewerIsShown, pictureUrl:contact.picture!, isFollowing: ns.isFollowing(contact.pubkey))
        }
        .task {
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

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        //        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
                        let f = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        //        let snowden = PreviewFetcher.fetchContact(pubkey)
        
        //        let testgif = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        
//        let testtransparentpfp = "7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194"
        
        
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NavigationStack {
                if let contact = PreviewFetcher.fetchContact() {
                    VStack {
                        ProfileView(contact: contact)
                    }
                }
            }
        }
    }
}
