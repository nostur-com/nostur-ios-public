//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import Nuke
import NukeUI
import CoreData
//import UIKit

// TODO: replying to trick:
// people.map(\.nameComponents).formatted(.list(memberStyle: .name(style:.short), type:.and)
// uitzoeken, from WWDC video

// A single note shown in a row in the MainTimelineView



struct NoteRowView: View {
    
    @Environment(\.managedObjectContext) var viewContext
//    @EnvironmentObject var cm:ConnectionManager
    var cm:SocketPool = .shared
    @EnvironmentObject var accountState:NosturState
    
    @ObservedObject var event:Event
//    var event:Event // TODO: Not sure need ObservedObject or not???
    
    @FetchRequest
    var taggedContacts:FetchedResults<Contact>
    
    @State var visible = false
    
    init(event: Event) {
        self.event = event
        let pubkeys = event.contactPubkeys()
        
        if (1 == 1) || (pubkeys == nil) {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "FALSEPREDICATE")
            )
        }
        else {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
            )
        }
    }
    
    var body: some View {
        
        VStack {
//        VStack(spacing:2) { // A TW EET
                        
            NavigationLink(value: event, label: {
                VStack (alignment: .leading) { // Vstack for retweeted thread
                    HStack(alignment: .top) { // Tweet
                        NavigationLink(value: event, label: {
                            VStack{ // profile image + thread line
                                // profile image
                                if (event.contact != nil) {
                                    NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                        ProfilePicView(pubkey: event.pubkey!, contact:event.contact)
                                    })
                                }
                                else {
                                    NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                        ProfilePicView(pubkey: event.pubkey!, contact:event.contact)
                                    })
                                }
                                Spacer()
                            }
                            .frame(height: 100)
//                            .padding(.leading, 10)
                        })
                        
                        VStack(alignment:.leading) {// Tweet container
                            HStack { // name + reply + context menu
                                if (visible) {
                                    
                                    NavigationLink(value: event, label: {
                                        VStack(alignment: .leading) { // Name + menu "replying to"
                                            HStack(spacing:2) {
                                                Text(event.contact?.authorName ?? "Anon") // Name
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.primary)
                                                    .fontWeight(.bold)
                                                    .lineLimit(1)
                                                
                                                Text("@\(event.contact?.username ?? event.authorKey) · \(event.ago)") //
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            ReplyingToFragment(event: event)
                                        }
                                    })
                                }
                                Spacer()
                            }.frame(height: 40).border(.red)
                            
                            NavigationLink(value: event, label: {
                                VStack(alignment: .leading) {
                                    NoteTextRenderView(event:event, taggedContacts:Array(taggedContacts))
                                    
                                    let WTF = Date(timeIntervalSince1970: TimeInterval(event.created_at))
                                        .formatted(.dateTime.hour().minute().second())
                                    
                                    Text("\(WTF)")
                                }
                            })

                           HStack {
                               if (visible) { FooterFragment(event: event) } 
                           }  .frame(height: 25)
//                            FooterFragment(event:event)
//                                .frame(height: 30)
                        }
//                        .padding(.trailing, 10).padding(.bottom, 5)
                    }
                }
            })
//            .frame(maxHeight: 1900)
            Divider()
        }
        .padding(10)
        .onAppear {
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (event.contact == nil) {
                print("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(event.pubkey!)")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
            }
        }
        
    }
}

struct FooterFragment: View {
//    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var event:Event
    
    var body: some View {
        HStack { // Footer stats
            Button {
                
            } label: {
                Label("\(event.repliesCount)", systemImage: "message")
            }
            Spacer()
            Button {
                
            } label: {
                Label("\(event.mentions)", systemImage: "arrow.2.squarepath")
            }
            Spacer()
            
            
            if (event.liked) {
                Label("\(event.likes)", systemImage: "heart.fill").foregroundColor(.red)
            }
            else {
                Button {
                    if (ns.account != nil) {
                        print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
                        event.liked = true
                        event.likes = event.likes + 1
                        ns.account?.addToLikes(event)
                        
                        // 1. create kind 7 event based on kind 1 event:    Event
                        let likeEvent = EventMessageBuilder.makeReactionEvent(reactingTo: event)
                        
                        // 2. sign that event with account keys             Account
                        guard let signedEvent = try? ns.signEvent(likeEvent) else {
                            print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                            return
                        }
                        
                        // 3. Save in core data                             NSManagedObjectContext
                        let savedEvent = Event.saveEvent(event: signedEvent, context: viewContext)
                        do {
                            try viewContext.save()
                        }
                        catch {
                            print("🔴🔴🔴🔴🔴 COULD NOT SAVE EVENT 🔴🔴🔴🔴🔴")
                            print(error)
                            return
                        }

                        // 4. publish that event                            SocketPool
                        print("Should send: \(NRelayMessage(event: savedEvent.toNEvent()).message)")
                        
                        print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
                    }
                } label: {
                    Label("\(event.likes)", systemImage: "heart")
                }
            }
//            Spacer()


            
//            Button {
//                print("GO")
//            } label: {
//                Label("\(event.repliesCount)", systemImage: "message")
//            }
//
//            Button {
//                print("GO")
//            } label: {
//                Label("\(event.likes)", systemImage: "heart")
//            }
            
//            Text("WTF FOOTER \(event.repliesCount)")
//            Image(systemName: "message")//.frame(height: 50)
//            Button(action: {
//                // Handle retweet action
//            }) {
////                Label("\(event.repliesCount)", systemImage: "message")
////                HStack {
//////                    Image(systemName: "message")
////                    Text("\(event.repliesCount)")
////                }//.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
//            }
//
//
//            Button {
//                print("A")
//            }  label: {
//                Label("\(event.repliesCount)", systemImage: "message")
////                HStack {
//////                    Image(systemName: "arrow.2.squarepath")
//////                    Text("\(event.mentions)")
////                    Label("\(event.repliesCount)", systemImage: "message")
////                }//.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
//            }
//
//            Button(action: {
//                // Handle like action
//            }) {
//                HStack {
//                    Image(systemName: "heart")
//                    Text("\(event.likes)")
//                }//.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
//            }
//

//            Button {
//                if (accountState.isBookmarked(event)) {
//                    accountState.removeBookmark(event)
//                }
//                else {
//                    accountState.addBookmark(event)
//                }
//            } label: {
//                if (accountState.isBookmarked(event)) {
//                    Image(systemName: "bookmark.fill")
//                        .foregroundColor(.orange)
//                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
//                }
//                else {
//                    Image(systemName: "bookmark")
//                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
//                }
//            }

        }.foregroundColor(.gray)
//            .padding(.top, 3)
    }
}

//struct FooterFragment: View {
////    @EnvironmentObject var accountState:AccountState
//    var event:Event
//
//    var body: some View {
//        HStack { // Footer stats
//
//
//            Label("\(event.repliesCount)", systemImage: "message")
//            Spacer()
//            Label("\(event.mentions)", systemImage: "arrow.2.squarepath")
//            Spacer()
//            Label("\(event.likes)", systemImage: "heart")
//            Spacer()
//
////            Button {
////                print("GO")
////            } label: {
////                Label("\(event.repliesCount)", systemImage: "message")
////            }
////
////            Button {
////                print("GO")
////            } label: {
////                Label("\(event.likes)", systemImage: "heart")
////            }
//
////            Text("WTF FOOTER \(event.repliesCount)")
////            Image(systemName: "message")//.frame(height: 50)
////            Button(action: {
////                // Handle retweet action
////            }) {
//////                Label("\(event.repliesCount)", systemImage: "message")
//////                HStack {
////////                    Image(systemName: "message")
//////                    Text("\(event.repliesCount)")
//////                }//.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
////            }
////
////
////            Button {
////                print("A")
////            }  label: {
////                Label("\(event.repliesCount)", systemImage: "message")
//////                HStack {
////////                    Image(systemName: "arrow.2.squarepath")
////////                    Text("\(event.mentions)")
//////                    Label("\(event.repliesCount)", systemImage: "message")
//////                }//.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
////            }
////
////            Button(action: {
////                // Handle like action
////            }) {
////                HStack {
////                    Image(systemName: "heart")
////                    Text("\(event.likes)")
////                }//.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
////            }
////
//
////            Button {
////                if (accountState.isBookmarked(event)) {
////                    accountState.removeBookmark(event)
////                }
////                else {
////                    accountState.addBookmark(event)
////                }
////            } label: {
////                if (accountState.isBookmarked(event)) {
////                    Image(systemName: "bookmark.fill")
////                        .foregroundColor(.orange)
////                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
////                }
////                else {
////                    Image(systemName: "bookmark")
////                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
////                }
////            }
//
//        }.foregroundColor(.gray)
////            .padding(.top, 3)
//    }
//}

struct NoteRowView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
        
        let event0 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event1 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        let event2 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        
        VStack {
            NoteRowView(event: event0!)
                .withPreviewEnvironment()
            NoteRowView(event: event1!)
                .withPreviewEnvironment()
            NoteRowView(event: event2!)
//                .flip()
                .withPreviewEnvironment()
            Spacer()
        }
    }
}



//struct FlipWrapper<Content: View>: UIViewRepresentable{
//    //The content to be flipped
//    @ViewBuilder let content: () -> Content
//    //Triggers the animation
//    func makeUIView(context: Context) -> UIView {
//        //Convert SwiftUI View to UIKit UIView
//        let view = UIHostingController(rootView: content()).view
//        view!.transform = CGAffineTransformMakeScale(1, -1)
//        view!.frame = view!.bounds
////        view = view!.transform.scaledBy(x: 1, y: -1)
//        return view!
//    }
//    func updateUIView(_ uiView: UIView, context: Context) {
//        uiView.transform = CGAffineTransformMakeScale(1, -1)
//        uiView.frame = uiView.bounds
//    }
//}
//
//
//extension View {
//    func flip() -> some View {
//        modifier(FlipViewModifier())
//    }
//}
//struct FlipViewModifier: ViewModifier {
//    func body(content: Content) -> some View {
//        FlipWrapper(content: { content })
//    }
//}
