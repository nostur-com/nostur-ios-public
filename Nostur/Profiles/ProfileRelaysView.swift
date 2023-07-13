////
////  ProfileRelaysView.swift
////  Nostur
////
////  Created by Fabian Lachman on 29/01/2023.
////
////
//
//import SwiftUI
//import SwiftyJSON
//
//// RELAYS ON USER PROFILE SCREEN
//struct ProfileRelaysView: View {
//    
//    @Environment(\.managedObjectContext) var viewContext
//    let sp:SocketPool = .shared
//    var clEvent:Event
//    var relays:[String : JSON]?
//    var cc:String
//    
//    init(clEvent:Event) {
//        self.clEvent = clEvent
////        let decoder = JSONDecoder()
//        cc = clEvent.content!
//            
////        guard let relays = try? decoder.decode([String : [[String: Int]]?].self, from: Data(clEvent.content!.utf8)) else {
////            return
////        }
////        self.relays = relays
////
//        // TODO: Remove SwiftyJSON code so we can remove package
//        if let jsonData = clEvent.content?.data(using: .utf8, allowLossyConversion: false) {
//            guard let jsonContent = try? JSON(data: jsonData) else {
//                return
//            }
//
//            if let relayDict = jsonContent.dictionary {
//                relays = relayDict
//            }
//        }
//    }
//    
//    var body: some View {
//        if relays != nil {
//            VStack {
//                ForEach(Array(relays!.keys), id:\.self) { relay in
//                    HStack {
//                        Text("\(relay)")
//                        Spacer()
//                        Button {
//                            let url = String(relay)
//                            do {
//                                let maybeSocket = sp.socketByUrl(url.description)
//                                if (maybeSocket != nil) {
//                                    maybeSocket!.client.connect()
//                                }
//                                else {
//                                    // create new
//                                    let newRelay = Relay(context: viewContext)
//                                    newRelay.url = url.description
//                                    newRelay.read = true
//                                    newRelay.write = true
//                                    newRelay.createdAt = Date.now
//                                    
//                                    
//                                    try viewContext.save()
//                                    let managedSocket = sp.addSocket(relayId: newRelay.objectID, url: url.description, read: true, write: true)
//                                    managedSocket.client.connect()
//                                }
//                            }
//                            catch {
//                                print("🔌🔴 Could not add relay \(error)")
//                            }
//                            
//                        } label: {
//                            if (sp.isUrlConnected(relay.description)) {
//                                Text("")
//                            }
//                            else {
//                                Text("Connect")
//                            }
//                        }
//                    }
//                    .padding()
//                    Divider()
//                }
//            }
//        }
//        else {
//            EmptyView()
//        }
//        
//    }
//}
//
//struct ProfileRelaysView_Previews: PreviewProvider {
//    static var previews: some View {
//        
//        
//        
//        ScrollView {
//            let clEventId = "3e030d91ac2b0c0ddb885e1aac05b33e07b1a131f725de7c9c6491a8cc817e1e"
//            let clEvent = PreviewFetcher.fetchEvent(clEventId)
//            
//            if (clEvent != nil) {
//                ProfileRelaysView(clEvent: clEvent!)
//            }
//        }
//        .withPreviewEnvironment()
//    }
//}
