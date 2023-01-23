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
    @EnvironmentObject var cm:ConnectionManager
    @State private var refresh: Bool = false 
    
    
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
                        if (relay.isConnected) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .opacity(1)
                            Text("Connected")
                            Spacer()
                            Button {
                                if let thisRelay = cm.relaySockets.first(where: { $0.relay == relay }) {
                                    print("Disconnecting: \(thisRelay.relay.url!)")
                                    thisRelay.disconnect()
//                                    refresh.toggle()
                                }
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
                                if let thisRelay = cm.relaySockets.first(where: { $0.relay == relay }) {
                                    print("Connecting: \(thisRelay.relay.url!)")
                                    thisRelay.connect()
                                }
                            } label: {
                                Text("Connect")
                            }
                        }
                    }
                }
            }
            Button {
                try! viewContext.save()
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

struct RelayEditView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        let cm = ConnectionManager()
        
        let relay = Relay(context: EventsProvider.preview.container.viewContext)
        relay.id = UUID()
        relay.url = "wss://nostr.bitcoin.sex"
        relay.read = true
        relay.write = false
        relay.createdAt = Date()
        
        return NavigationStack {
            RelayEditView(relay: relay)
                .environment(\.managedObjectContext, EventsProvider.preview.container.viewContext)
                .environmentObject(cm)
        }
    }
}
