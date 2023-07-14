////
////  ProfilePicView.swift
////  Nostur
////
////  Created by Fabian Lachman on 19/01/2023.
////
//
//import SwiftUI
//import SwiftyJSON
//
//struct ProfileRelays: View {
//
//    @Environment(\.managedObjectContext) var viewContext
//    let sp:SocketPool = .shared
//    @ObservedObject var relayEvent:Event
//
//    var relayTags:[(String, String, String?)] {
//        relayEvent.fastTags.filter { $0.0 == "r" }
//    }
//
//    init(relayEvent:Event) {
//        self.relayEvent = relayEvent
//    }
//
//    var body: some View {
//        VStack {
//            ForEach(relayTags.indices, id:\.self) { index in
//                HStack {
//                    Text("\(relayTags[index].1) (\(relayTags[index].2 == nil ? "read & write" : relayTags[index].2!))")
//                    Spacer()
//                    Button {
//                        let url = String(relayTags[index].1)
//                        do {
//                            let maybeSocket = sp.socketByUrl(url)
//                            if (maybeSocket != nil) {
//                                maybeSocket!.client.connect()
//                            }
//                            else {
//                                // create new
//                                let newRelay = Relay(context: viewContext)
//                                newRelay.url = url.description
//                                newRelay.read = true
//                                newRelay.write = true
//                                newRelay.createdAt = Date.now
//
//
//                                try viewContext.save()
//                                let managedSocket = sp.addSocket(relayId: newRelay.objectID, url: url, read: true, write: true)
//                                managedSocket.client.connect()
//                            }
//                        }
//                        catch {
//                            print("🔌🔴 Could not add relay \(error)")
//                        }
//
//                    } label: {
//                        if (sp.isUrlConnected(relayTags[index].1)) {
//                            Text("")
//                        }
//                        else {
//                            Text("Connect")
//                        }
//                    }
//                }
//                .padding()
//                Divider()
//            }
//        }
//    }
//}
//
//struct ProfileRelays_Previews: PreviewProvider {
//    static var previews: some View {
//
//        ScrollView {
//            let relayEventId = "648eedac317d52339f71d1b505930ee4c369256d129f2d7e32815cb2d6d6db95"
//            let relayEvent = PreviewFetcher.fetchEvent(relayEventId)
//
//            if (relayEvent != nil) {
//                ProfileRelays(relayEvent: relayEvent!)
//            }
//        }
//        .withPreviewEnvironment()
//    }
//}
