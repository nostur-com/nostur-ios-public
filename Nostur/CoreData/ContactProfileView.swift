//
//  UserProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI
import CoreData
import Nuke
import NukeUI

struct ContactProfileView: View {
    
    @EnvironmentObject var cm:ConnectionManager
    
    var pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
    @FetchRequest
    var metaDataEvents: FetchedResults<Event>
    
    @FetchRequest
    var contactListEvents: FetchedResults<Event>
    
    init(pubkey:String) {
        self.pubkey = pubkey
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
        
        _metaDataEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 0", pubkey)
        )
        
        _contactListEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 3", pubkey)
        )
    }
    
    @ViewBuilder
    var body: some View {
        
        if (contacts.first == nil) {
            Text("No contact for pubkey: \(pubkey)")
        }
        
        if (metaDataEvents.first == nil) {
            Text("No metadata events for pubkey: \(pubkey)")
                .onAppear {
                    print("☎️ ContactProfileView: REQ metadata for pubkey \(pubkey)")
                    cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
                }
        }
        
        if (contactListEvents.first == nil) {
            Text("No contact list events for pubkey: \(pubkey)")
        }
        
        let contactProfile = ContactProfile(contact: contacts.first!, clEvent: contactListEvents.first)
        ContactProfileViewInner(contactProfile: contactProfile)
    }
    
}

struct ContactProfileViewInner: View {
    
    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var cm:ConnectionManager
    
    @ObservedObject var contactProfile: ContactProfile
    
    var body: some View {
        ScrollView {
            ZStack() {
                GeometryReader { geo in
                    if (contactProfile.contact.banner != nil) {
                                
                    LazyImage(url: URL(string: contactProfile.contact.banner!)) { state in
                        if let image = state.image {
                            image // Displays the loaded image
                        }
                        else {
                            Image("NosturBanner")
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: 150)
//                                .clipped()
                        }
                    }
                    .processors([ImageProcessors.Resize(width: geo.size.width)])
                        .animation(nil)
                        .priority(.high)
                        .pipeline(ImagePipeline {
                            $0.dataLoader = DataLoader(configuration: {
                                // Disable disk caching built into URLSession
                                let conf = DataLoader.defaultConfiguration
                                conf.urlCache = nil
                                return conf
                            }())

                            $0.imageCache = ImageCache()
                            $0.dataCache = try! DataCache(name: "com.nostur.2140.banner")
                        }).frame(width: geo.size.width, height: 150)
//                            .clipped()
                        
                    }
                    else {
                        HStack {
                            Image("NosturBanner")
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: 150)
                        }
                    }
                }
                
                HStack {
                    VStack {
                        ProfilePicView(pubkey: contactProfile.publicKey, contact: contactProfile.contact)
                            .frame(maxWidth:75, maxHeight:75)
                            .clipShape(Circle())
                            .offset(x: 10, y: 150-37.5)
                        Spacer()
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading) {
                    Rectangle().background(.clear).foregroundColor(.clear).frame(height:150) // Spacer to push content below header pic
                    
                    HStack(alignment:.top) {
                        
                        Spacer()
                        
                        Button {
                            if accountState.isFollowing(contactProfile.publicKey) {
                                accountState.unfollow(contactProfile.publicKey)
                            } else {
                                accountState.follow(contactProfile.publicKey, cm: cm)
                            }
                        } label: {
                            Text(accountState.isFollowing(contactProfile.publicKey) ? "Following" : "Follow")
                                .frame(height: 30)
                                .padding(.horizontal, 25)
                            //.padding(.vertical, 10)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.primary)
                                .background(.clear)
                                .cornerRadius(20)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.primary, lineWidth: 1)
                                }
                        }
                    }
                    
                    Text("\(contactProfile.authorName)").font(.headline)
                    HStack {
                        Text("@\(contactProfile.username)").foregroundColor(.secondary)
                        
                        
                        Menu {
                            Button {
                                UIPasteboard.general.string = contactProfile.publicKey
                            } label: {
                                Label("Copy public key hex \(contactProfile.publicKey)...", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                UIPasteboard.general.string = contactProfile.npub
                            } label: {
                                Label("Copy npub \(contactProfile.npub)...", systemImage: "doc.on.clipboard")
                            }
                        } label: {
                            Image(systemName: "person.badge.key.fill")
//                            Text("···")
//                                .foregroundColor(.secondary)
//                                .padding(.top, 0)
//                                .padding(.bottom, 10)
//                                .padding(.leading, 20)
//                                .padding(.trailing, 10)
                            
                        }
                    }
                    
                    Text("\n\(contactProfile.about)")
                    
                    //                Text("Followed by ppl you know...")
                    // Tweets here
                    Text("Tweets / Liked").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                    //                        TweetView(tweet: Tweet())
                    //                        TweetView(tweet: Tweet())
                    
                    
                    if let pubkeys = contactProfile.contactsPubkeys() {
                        
                        Text("Following").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                        
                        
                        LazyVStack {
                            ForEach(pubkeys, id: \.self) { pubkey in
                                ContactProfileRowView(pubkey: pubkey)
                                Divider()
                            }
                        }
                        
                        Spacer()
                        
                    }
                }.padding(10)
                Spacer()
            }
        }
        .onAppear {
            // TODO banner update logic...
            // new field .banner in metadata, but not in existing contact
            // how/when to update?
            if (contactProfile.metaData == nil) {
                print("☎️ CPVinner: REQ metadata for pubkey \(contactProfile.publicKey)")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: contactProfile.publicKey)))
            }
            

            if (contactProfile.clEvent == nil) {
                print("📙 CPVinner REQ contact list for pubkey \(contactProfile.publicKey)")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: contactProfile.publicKey)))
            }

            if let pubkeys = contactProfile.contactsPubkeys(), pubkeys.count > 0 {
                print("📙📙📙📙📙 REQ META DATA FOR CL P TAGS")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
            }
            
        }
        .ignoresSafeArea(edges: .top)
    }
}


// FOR PREVIEW
struct ContactProfileViewWrapper: View {
    
    @EnvironmentObject var cm:ConnectionManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(format: "pubkey == %@", "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(fetchRequest:Event.setMetaDataEvents(byAuthorPubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"))
    var metaDataEvents: FetchedResults<Event>
    
    @FetchRequest(fetchRequest:Event.contactListEvents(byAuthorPubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"))
    var contactListEvents: FetchedResults<Event>
    
    
    @ViewBuilder
    var body: some View {
        
        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0" // todo
        
        if (contacts.first == nil) {
            Text("No contact for pubkey: \(pubkey)")
        }
        
        if (metaDataEvents.first == nil) {
            Text("No metadata events for pubkey: \(pubkey)")
            .onAppear {
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
            }
        }
        
        if (contactListEvents.first == nil) {
            Text("No contact list events for pubkey: \(pubkey)")
                .onAppear {
                    cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: pubkey)))
                }
        }
        
        let contactProfile = ContactProfile(contact: contacts.first!, clEvent: contactListEvents.first)
        ContactProfileViewInner(contactProfile: contactProfile)
        
    }
    
}

struct ContactProfileView_Previews: PreviewProvider {
    
//    static var previewUserDefaults: UserDefaults = {
//                let d = UserDefaults(suiteName: "preview_user_defaults")!
//
//        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
//
//        return d
//            }()
    
    static var previews: some View {
        
//        let cm = ConnectionManager()
//
//        let accountState = AccountState(viewContext: EventsProvider.preview.container.viewContext)
        
        return ContactProfileViewWrapper()
            .withPreviewEnvironment()
        
        
//            .defaultAppStorage(previewUserDefaults)
//            .environment(\.managedObjectContext,
//                          EventsProvider.preview.container.viewContext)
//            .environmentObject(accountState)
//            .environmentObject(cm)
    }
}

