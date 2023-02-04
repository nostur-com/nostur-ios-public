//
//  RelayEditView.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/01/2023.
//

import SwiftUI

struct RelayEditView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var relay: Relay
    @ObservedObject var socket: ManagedConnection
    @State private var refresh: Bool = false
    var sp:SocketPool = .shared
    
    var body: some View {
        return VStack {
            Form {
                Section(header: Text("Relay URL") ) {
                    TextField("wss://nostr.relay.url.here", text: Binding($relay.url)!)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                Section(header: Text("Relay settings") ) {
                    Toggle(isOn: $relay.read) {
                        Text("Receive events")
                    }
                    Toggle(isOn: $relay.write) {
                        Text("Post events") .background(refresh ? Color.clear : Color.clear)
                    }
                }
                Section(header: Text("Status") ) {
                    HStack {
                        if (socket.isConnected) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .opacity(1)
                            Text("Connected")
                            Spacer()
                            Button {
                                socket.connection.disconnect()
                            } label: {
                                Text("Disconnect")
                            }
                        }
                        else {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.gray)
                                .opacity(0.2)
                            Text("Disconnected")
                            Spacer()
                            Button {
                                socket.connection.connect()
                            } label: {
                                Text("Connect")
                            }
                        }
                    }
                }
            }
            Button {
                try! viewContext.save()
                // Update existing connections
                // url change?
                if (relay.url != nil && socket.url != relay.url?.lowercased()) {
                    socket.connection.disconnect()
                    sp.removeSocket(relay.objectID)
                    _ = sp.addSocket(relayId: relay.objectID, url: relay.url!, read: relay.read, write: relay.write)
                }
                else {
                    // read/write change?
                    socket.write = relay.write
                    socket.read = relay.read
                }
                dismiss()
            } label: {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 220, height: 50)
                    .background(Color.accentColor)
                    .cornerRadius(15.0)
            }
            Spacer()
            
        }.onAppear {

            
        }
    }
}

//struct RelayEditView_Previews: PreviewProvider {
//    
//    static var previews: some View {        
//        let relay = Relay(context: EventsProvider.preview.container.viewContext)
//        relay.id = UUID()
//        relay.url = "wss://nostr.bitcoin.sex"
//        relay.read = true
//        relay.write = false
//        relay.createdAt = Date()
//        
//        return NavigationStack {
//            RelayEditView(relay: relay)
//                .withPreviewEnvironment()
//        }
//    }
//}
