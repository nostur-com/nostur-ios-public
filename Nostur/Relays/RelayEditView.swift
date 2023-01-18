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
    
    
    var body: some View {
        
//        var isConnected = ConnectionManager.shared.relaySockets.filter { $0.relay == relay }.first?.isConnected ?? false
        
        let isConnected = ConnectionManager.shared.relaySockets.first { $0.relay == relay }?.isConnected ?? false
        
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
                        Text("Post events")
                    }
                }
                Section(header: Text("Status") ) {
                    HStack {
                        if (isConnected) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .opacity(1)
                            Text("Connected")
                        }
                        else {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.gray)
                                .opacity(0.2)
                            Text("Disconnected")
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
                    .background(.cyan)
                    .cornerRadius(15.0)
            }
            Spacer()
            
        }.onAppear {

            
        }
    }
}

struct RelayEditView_Previews: PreviewProvider {
    static var previews: some View {
        
        let relay = Relay(context: PersistenceController.preview.container.viewContext)
        relay.id = UUID()
        relay.url = "wss://nostr.bitcoin.sex"
        relay.read = true
        relay.write = false
        relay.createdAt = Date()
        
        return NavigationStack {
            RelayEditView(relay: relay)
        }
    }
}
