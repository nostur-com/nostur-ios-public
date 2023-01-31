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
    
    var pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
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
            Text("Trying to fetch...").onAppear {
                print("🟢 ProfileByPubkey.onAppear no contact so REQ.0: \(pubkey)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
            }
        }
    }
}

class ImageProcessing {
    static public var shared = ImageProcessing()
    
    var pipeline:ImagePipeline
    var bannerPipeline:ImagePipeline
    
    init() {
        pipeline = ImagePipeline {
            $0.dataCache = try? DataCache(name: "com.nostur.2140.picture")
            $0.dataCachePolicy = .storeEncodedImages
        }
        
        bannerPipeline = ImagePipeline {
            $0.dataCache = try? DataCache(name: "com.nostur.2140.banner")
            $0.dataCachePolicy = .storeEncodedImages
        }
    }
    
}

struct Profile: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    
    var contact:Contact
    var pubkey:String
    
    @FetchRequest
    var clEvents:FetchedResults<Event>
    
    @State var activeTab = "NOTES"

    init(contact:Contact) {
        self.contact = contact
        self.pubkey = contact.pubkey!
        
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
                                Image("NosturBanner")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: 150)
                                //                                .clipped()
                            }
                        }
                        .processors([ImageProcessors.Resize(width: geo.size.width)])
                        .animation(nil)
                        .priority(.normal)
                        .pipeline(ImageProcessing.shared.bannerPipeline)
//                        .pipeline(ImagePipeline {
//                            // TODO: volgens mij klopt niet
//                            /// moet ergens anders clean 1x doen ipv iedere keer voor image
//                            $0.dataLoader = DataLoader(configuration: {
//                                // Disable disk caching built into URLSession
//                                let conf = DataLoader.defaultConfiguration
//                                conf.urlCache = nil
//                                return conf
//                            }())
//
//                            $0.imageCache = ImageCache()
//                            $0.dataCache = try! DataCache(name: "com.nostur.2140.banner")
//                        })
                        .frame(width: geo.size.width, height: 150)
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
                        ProfilePicView(pubkey: contact.pubkey!, contact: contact)
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
                        
                        FollowButton(isFollowing: ns.isFollowing(contact))
                    }
                    
                    
                    Text("\(contact.authorName)").font(.headline)
                    HStack {
                        Text("@\(contact.username)").foregroundColor(.secondary)
                        
                        Menu {
                            Button {
                                UIPasteboard.general.string = pubkey
                            } label: {
                                Label("Copy public key hex \(pubkey)...", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                UIPasteboard.general.string = Contact.npub(pubkey)
                            } label: {
                                Label("Copy npub \(Contact.npub(pubkey))...", systemImage: "doc.on.clipboard")
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

                    Text("\n\(String(contact.about ?? "(No information)"))")
                                        
                    ControlGroup {
                        Button { importNotes() } label: { Text("Import") }
                        Button { activeTab = "NOTES" } label: {
                            Label("Notes", systemImage: "bubble.left.and.bubble.right")
                        }
                        Button { activeTab = "FOLLOWING" } label: {
                            Label("Following", systemImage: "person.3.sequence")
                        }
                        Button { activeTab = "LIKES" } label: {
                            Label("Likes", systemImage: "hand.thumbsup")
                        }
                        Button { activeTab = "RELAYS"} label: {
                            Label("Relays", systemImage: "server.rack")
                        }
                    }
                    
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
                    
                    if (activeTab == "LIKES") {
                        ProfileLikesView(pubkey: pubkey)
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
                }.padding(10)
                //                Spacer()
            }
        }
        .ignoresSafeArea(edges: .top)
//        .onReceive(loopyRunny) { time in
//            let readyForImportQueue = MessageParser.shared.readyForImportQueue
//            do {
//                try Importer.shared.importEvents(queue: readyForImportQueue)
//            }
//            catch {
//                print("🟣🟣🟣 something wrong")
//                print(error)
//            }
//        }
    }
}

extension Profile {
    private func importNotes() {
        Task { await Importer.shared.importEvents() }
    }
}

struct FollowButton: View {
    @Environment(\.colorScheme) var colorScheme
    var isFollowing: Bool = false

    var body: some View {

        let whiteColor = colorScheme == .light ? Color.white : Color.black
        let blackColor = colorScheme == .light ? Color.black : Color.white

        Text(isFollowing ? "Following" : "Follow")
            .lineLimit(1)
            .frame(width: 65, height: 30)
            .padding(.horizontal, 25)
        //.padding(.vertical, 10)
            .font(.caption.weight(.heavy))
            .foregroundColor(isFollowing ? blackColor : whiteColor)
            .background(isFollowing ? whiteColor : blackColor)
            .cornerRadius(20)
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.gray, lineWidth: 1)
            }
    }
}


struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        let snowden = PreviewFetcher.fetchContact(pubkey)
        //        let clEvent = PreviewFetcher.fetchEvents(pubkey, kind: 3).first!
        //
        Profile(contact:snowden!)
            .withPreviewEnvironment()
        
    }
}
