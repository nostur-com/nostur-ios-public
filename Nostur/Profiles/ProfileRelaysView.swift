//
//  ProfileRelaysView.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import SwiftUI
import SwiftyJSON

// NOTES ON USER PROFILE SCREEN
struct ProfileRelaysView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var sp:SocketPool
    var clEvent:Event
    var relays:[String : JSON]?
    var cc:String
    
    init(clEvent:Event) {
        self.clEvent = clEvent
//        let decoder = JSONDecoder()
        cc = clEvent.content!
            
//        guard let relays = try? decoder.decode([String : [[String: Int]]?].self, from: Data(clEvent.content!.utf8)) else {
//            return
//        }
//        self.relays = relays
//
        if let jsonData = clEvent.content?.data(using: .utf8, allowLossyConversion: false) {
            guard let jsonContent = try? JSON(data: jsonData) else {
                return
            }

            if let relayDict = jsonContent.dictionary {
                relays = relayDict
            }
        }
    }
    
    var body: some View {
        if relays != nil {
            VStack {
                List {
                    ForEach(Array(relays!.keys), id:\.self) { relay in
                        HStack {
                            Text("\(relay)")
                            Spacer()
                            Button {
                                let url = String(relay)
                                _ = sp.addSocket(url: url, read:true, write: true)
                                let r = Relay()
                                r.url = url
                                r.read = true
                                r.write = true
                                r.createdAt = Date.now
                                try! viewContext.save()
                                
                            } label: {
                                if (sp.isUrlConnected(String(relay))) {
                                    Text("")
                                }
                                else {
                                    Text("Connect")
                                }
                            }
                        }
                    }
                }.listStyle(.insetGrouped)
                    .frame(height: 400)
                Spacer()
            }
        }
        else {
            Text("relays is nil")
        }
        
    }
}

struct ProfileRelaysView_Previews: PreviewProvider {
    static var previews: some View {
        
        let clEventId = "3e030d91ac2b0c0ddb885e1aac05b33e07b1a131f725de7c9c6491a8cc817e1e"
        let clEvent = PreviewFetcher.fetchEvent(clEventId)
        
        ScrollView {
            ProfileRelaysView(clEvent: clEvent!)
                .withPreviewEnvironment()
        }
    }
}
