////
////  ProfileView.swift
////  Nostur
////
////  Created by Fabian Lachman on 24/01/2023.
////
//
//import SwiftUI
//import NukeUI
//import Nuke
//
//
//
//
//struct ProfileRowView: View {
//    
//    var pubkey:ContactPubkey
////    var contact:Contact? = nil
////    var clEvent:Event? = nil
//    
//    @FetchRequest
//    var contacts:FetchedResults<Contact>
//    
//    init(pubkey:String) {
//        self.pubkey = pubkey
//        
//        _contacts = FetchRequest(
//            sortDescriptors: [],
//            predicate: NSPredicate(format: "pubkey == %@", pubkey)
//        )
//    }
//    
//    var body: some View {
//        if (contacts.first != nil) {
//            NavigationLink(value: contacts.first!) {
//                ProfileRowInner(pubkey: pubkey, contacts: contacts)
//            }
//        }
//        else {
//            NavigationLink(value: pubkey) {
//                ProfileRowInner(pubkey: pubkey, contacts: contacts)
//            }
//        }
//    }
//}
//
//struct ProfileRowInner: View {
//
//    @EnvironmentObject var accountState:AccountState
//    @EnvironmentObject var cm:ConnectionManager
//    
//    var pubkey:String
//    var contacts:FetchedResults<Contact>
//    
//    var body: some View {
//        HStack {
//            VStack {
//                ProfilePicView(pubkey: pubkey, contact: contacts.first)
//                    .frame(width: 50, height: 50)
//                    .clipShape(Circle())
//                Spacer()
//            }
//            VStack(alignment: .leading) {
//                HStack {
//                    VStack(alignment: .leading) {
//                        Text(contacts.first?.authorName ?? "Anon").font(.headline).foregroundColor(.primary)
//                            .lineLimit(1)
//                        Text("@\(contacts.first?.username ?? String(pubkey.prefix(5)))").font(.subheadline).foregroundColor(.secondary)
//                            .lineLimit(1)
//                    }.multilineTextAlignment(.leading)
//                    Spacer()
//                    Button {
//                        if accountState.isFollowing(pubkey) {
//                            accountState.unfollow(pubkey)
//                        } else {
//                            accountState.follow(pubkey, cm: cm)
//                        }
//                    } label: {
//                        FollowButton(isFollowing:accountState.isFollowing(pubkey))
//                    }
//                }
//                Text(contacts.first?.about ?? "").foregroundColor(.primary)
//                    .multilineTextAlignment(.leading)
//                Spacer()
//            }
//        }
//        .onAppear {
//            if (contacts.first == nil) {
//                print("🟢 ProfileRowInner.onAppear no contacts so REQ.0: \(pubkey)")
//                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
//            }
//        }
//    }
//}
//
//
//struct OnlyPubkeyRow_Previews: PreviewProvider {
//    static var previews: some View {
//        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
//        let pubkey = "1e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
//        
//        ProfileRowView(pubkey: pubkey)
//            .withPreviewEnvironment()
//    }
//}
//
//struct ProfileRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
//        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
//        
//        ProfileRowView(pubkey: pubkey)
//            .withPreviewEnvironment()
//    }
//}
//
////struct NoClEventRow_Previews: PreviewProvider {
////    static var previews: some View {
////        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
////        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
//////        let contact = PreviewFetcher.fetchContact(pubkey)
////
////        ProfileRowView(pubkey: pubkey)
////            .withPreviewEnvironment()
////    }
////}
//
////struct ProfileRowView_Previews: PreviewProvider {
////    static var previews: some View {
////        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
////        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
////        let contact = PreviewFetcher.fetchContact(pubkey)
////        let clEvent = PreviewFetcher.fetchEvents(pubkey, kind: 3).first!
////
////        ProfileRowView(pubkey: pubkey, contact: contact, clEvent: clEvent)
////            .withPreviewEnvironment()
////    }
////}
