//
//  PRofile.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct ProfileByPubkey: View {
    
    @EnvironmentObject var sp:SocketPool
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    
    var pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
    let timeOut = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
        
    
    init(pubkey:String) {
        self.pubkey = pubkey
        
        _contacts = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        if (contacts.first != nil) {
            Profile(contact: contacts.first!)
        }
        else {
            ProgressView().onAppear {
                print("🟢 ProfileByPubkey.onAppear no contact so REQ.0: \(pubkey)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
            }
            .onReceive(timeOut) { firedDate in
                timeOut.upstream.connect().cancel()
                if ns.account?.publicKey == pubkey {
                    nav.navigateTo(ViewPath.Account(account: ns.account!))
                }
            }
        }
    }
}

struct Profile: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    @EnvironmentObject var nav:NavigationModel
    @Environment(\.managedObjectContext) var viewContext
    
    @ObservedObject var contact:Contact
    var pubkey:String
    let hideBadges:Bool
    
    @FetchRequest
    var clEvents:FetchedResults<Event>
    
    @State var activeTab = "NOTES"
    @State var isFollowing = false
    @State var profilePicViewerIsShown = false
    @State var navigationTitle = ""
    
    init(contact:Contact) {
        self.contact = contact
        self.pubkey = contact.pubkey
        self.hideBadges = SettingsStore.shared.hideBadges
        
        _clEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 3", pubkey)
        )
    }
    
    var body: some View {
        ScrollView {
            ZStack() {
                GeometryReader { geo in
                    if (contact.banner != nil) {
                        LazyImage(url: URL(string: contact.banner!)) { state in
                            if let image = state.image {
                                image // Displays the loaded image
                            }
                            else {
                                Rectangle()
                                    .foregroundColor(.gray)
//                                    .resizable()
//                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: 150)
                                //                                .clipped()
                            }
                        }
                        .processors([ImageProcessors.Resize(width: geo.size.width)])
                        .animation(nil)
                        .priority(.normal)
                        .pipeline(ImageProcessing.shared.bannerPipeline)
                        .frame(width: geo.size.width, height: 150)
                    }
                    else {
                        HStack {
                            Rectangle()
                                .foregroundColor(.gray)
//                                .resizable()
//                                .scaledToFill()
                                .frame(width: geo.size.width, height: 150)
                        }
                    }
                }
                
                HStack {
                    VStack {
                        ProfilePicView(pubkey: contact.pubkey, contact: contact, size: 75)
                            .offset(x: 10, y: 150-37.5)
                            .onTapGesture {
                                if (contact.picture != nil) {
                                    profilePicViewerIsShown = true
                                }
                            }
                        Spacer()
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading) {
                    Rectangle().background(.clear).foregroundColor(.clear).frame(height:150) // Spacer to push content below header pic
                    
                    HStack(alignment:.top) {
                        if (!hideBadges) {
                            ProfileBadgesContainer(pubkey: contact.pubkey)
                                .offset(x: 85, y: 0)
                        }
                        
                        Spacer()
                        
                        ProfileLightningButton(contact: contact)
                        
                        if (contact.pubkey != ns.account?.publicKey) {
                            Button {
                                if (isFollowing) {
                                    isFollowing = false
                                    ns.unfollow(contact)
                                }
                                else {
                                    print("chaning isFollowing to true 1")
                                    isFollowing = true
                                    ns.follow(contact)
                                    print("chaning isFollowing to true 2")
                                    //                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
                                }
                            } label: {
                                FollowButton(isFollowing:isFollowing)
                            }
                            .onAppear {
                                if (ns.isFollowing(contact)) {
                                    isFollowing = true
                                }
                            }
                        }
                        else {
                            Button {
                                navigateToAccount()
                            } label: {
                                Text("Edit profile")
                            }
                            .buttonStyle(NosturButton())
                        }
                    }
                    
                    
                    HStack(spacing:1) {
                        Text("\(contact.authorName) ").font(.headline)
                        if (contact.nip05veried) {
                            Group {
                                Image(systemName: "checkmark.seal.fill")
                                Text(contact.nip05domain).font(.footnote)
                            }.foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text("@\(contact.username)").foregroundColor(.secondary)
                        Menu {
                            Button {
                                UIPasteboard.general.string = pubkey
                            } label: {
                                Label("Copy public key hex \(String(pubkey.prefix(11)))...", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                UIPasteboard.general.string = Contact.npub(pubkey)
                            } label: {
                                Label("Copy npub \(String(Contact.npub(pubkey).prefix(11)))...", systemImage: "doc.on.clipboard")
                            }
                        } label: {
                            Image(systemName: "person.badge.key.fill")
                        }
                        PrivateNoteToggle(contact: contact)
                        if (ns.followsYou(contact)) {
                            Text("Follows you").font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary)
                                .opacity(0.7)
                                .cornerRadius(13)
                        }
                        
                    }
                    
                    Text("\n\(String(contact.about ?? "(No information)"))")
                    
                    HStack {
                        Text("\n**\(contact.followingPubkeys.count)** Following")

                        Text("\n**??** Followers")
                            .onTapGesture {
                                activeTab = "FOLLOWERS"
                            }
                        //                        Text("\n**\(contact.followingPubkeys.count)** Followers")
                    }
                    
                    ControlGroup {
                        //                        Button { importNotes() } label: { Text("Import") }
                        Button { activeTab = "NOTES" } label: {
                            Label("Notes", systemImage: "bubble.left.and.bubble.right")
                        }
                        Button { activeTab = "FOLLOWING" } label: {
                            Label("Following", systemImage: "person.3.sequence")
                        }
                        Button { activeTab = "LIKES" } label: {
                            Label("Likes", systemImage: "hand.thumbsup")
                        }
                        Button { activeTab = "ZAPS" } label: {
                            Label("Zaps", systemImage: "bolt")
                        }
                        Button { activeTab = "RELAYS"} label: {
                            Label("Relays", systemImage: "server.rack")
                        }
                    }
                    
                    Group {
                        if (activeTab == "NOTES") {
                            ProfileNotesView(pubkey: pubkey)
                                .padding(.vertical, 10)
                        }
                        
                        if (activeTab == "FOLLOWING") {
                            VStack {
                                if clEvents.count != 0, let pubkeys = clEvents.first!.contactPubkeys() {
                                    
                                    Text("Following").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                                    
                                    ContactList(pubkeys: pubkeys)
                                }
                                else {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .padding(50)
                                        Spacer()
                                            .onAppear {
                                                print("🟢 ProfileView.onAppear no clEvent so REQ.3: \(pubkey)")
                                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
                                            }
                                    }
                                }
                            }
                        }
                        
                        if (activeTab == "FOLLOWERS") {
                            
                            Text("Followers").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                            
                            FollowersList(pubkey: contact.pubkey)
                        }
                        
                        if (activeTab == "LIKES") {
                            ProfileLikesView(pubkey: pubkey)
                                .padding(.vertical, 10)
                        }
                        
                        if (activeTab == "ZAPS") {
                            ProfileZapsView(contact: contact)
                                .padding(.vertical, 10)
                        }
                        
                        if (activeTab == "RELAYS") {
                            VStack {
                                if clEvents.count != 0 {
                                    ProfileRelaysView(clEvent: clEvents.first!)
                                    
                                }
                                else {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .padding(50)
                                        Spacer()
                                    }
                                    .onAppear {
                                        print("🟢 ProfileView.onAppear no clEvent so REQ.3: \(pubkey)")
                                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        
                    }
                }.padding(10)
                //                Spacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("") // dont know how to hide contact.authorName, but DO show in next view back button
        .task {
            if (NIP05.shouldVerify(contact)) {
                if (await NIP05.verify(nip05: contact.nip05!, expectedPubkey: contact.pubkey)) {
                    await viewContext.perform {
                        contact.nip05verifiedAt = Date.now
                        // TODO: Crashed preview???
                        do { try! viewContext.save() }
                        catch { print("w🚗at") }
                    }
                    print("👍👍 nip05 verified \(contact.pubkey) \(contact.nip05!) ")
                }
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
                            print("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                        }
                    }
                }
                else if let lud06 = contact.lud06, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            print("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                        }
                    }
                }
            }
            catch {
                print("problem in lnurlp")
                print(error)
            }
        }
        .onChange(of: contact.nip05) { nip05 in
            if (NIP05.shouldVerify(contact)) {
                Task {
                    if (await NIP05.verify(nip05: contact.nip05!, expectedPubkey: contact.pubkey)) {
                        await viewContext.perform {
                            contact.nip05verifiedAt = Date.now
                            do { try viewContext.save() }
                            catch { print("w🚗at") }
                        }
                        print("👍👍 nip05 verified \(contact.pubkey) \(contact.nip05!) ")
                    }
                }
            }
        }
        .task {
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndBadges(pubkey: pubkey)))
        }
        .fullScreenCover(isPresented: $profilePicViewerIsShown) {
            ProfilePicFullScreenSheet(profilePicViewerIsShown: $profilePicViewerIsShown, pictureUrl:contact.picture!)
        }
    }
}

extension Profile {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {

        }
    }
}

struct ProfilePicFullScreenSheet: View {
    
    @Binding var profilePicViewerIsShown:Bool
    var pictureUrl:String
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(30)
                        .onTapGesture {
                            profilePicViewerIsShown = false
                        }
                }
                Spacer()
            }
            VStack {
                LazyImage(url: URL(string: pictureUrl)) { state in
                    if let image = state.image {
                        image.scaledToFit()
                    }
                    else {
                        ProgressView()
                    }
                }
            }
            .onTapGesture {
                profilePicViewerIsShown = false
            }
        }
    }
}

extension Profile {
    private func importNotes() {
        Task { await Importer.shared.importEvents() }
    }
    
    private func navigateToAccount() {
        if (ns.account != nil) {
            nav.navigateTo(ViewPath.Account(account: ns.account!))
        }
    }
}

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
//        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        let snowden = PreviewFetcher.fetchContact(pubkey)
        //        let clEvent = PreviewFetcher.fetchEvents(pubkey, kind: 3).first!
        //
        if (snowden != nil) {
            Profile(contact:snowden!)
                .withPreviewEnvironment()
        }
        
    }
}
