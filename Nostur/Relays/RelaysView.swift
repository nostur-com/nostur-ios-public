//
//  RelaysView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI
import CoreData

struct RelayRowView: View {
    @ObservedObject var relay:Relay
    @StateObject var socket:NewManagedClient
    
    var body: some View {
        HStack {
            
            if (socket.isConnected) {
                Image(systemName: "circle.fill").foregroundColor(.green)
                    .opacity(1.0)
            }
            else {
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
                    .opacity(0.2)
            }
            
            Text("\(relay.url ?? "(Unknown)")")
            
            Spacer()
            
            Image(systemName:"arrow.down.circle.fill").foregroundColor(relay.read ? .green : .gray)
                .opacity(relay.read ? 1.0 : 0.2)
                .onTapGesture {
                    relay.read.toggle()
                    socket.read = relay.read
                    try! relay.managedObjectContext!.save()
                }
            
            Image(systemName:"arrow.up.circle.fill").foregroundColor(relay.write ? .green : .gray)
                .opacity(relay.write ? 1.0 : 0.2)
                .onTapGesture {
                    relay.write.toggle()
                    socket.write = relay.write
                    try! relay.managedObjectContext!.save()
                }
        }
    }
}

struct RelaysView: View {
    
    @State var createRelayPresented = false
    @State var editRelay:Relay?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Relay.createdAt, order: .forward)],
        animation: .default)
    var relays: FetchedResults<Relay>

    let sp:SocketPool = .shared

    func socketForRelay(relay: Relay) -> NewManagedClient {
        guard let socket = sp.sockets[relay.objectID] else {
            let addedSocket = try! sp.addSocket(relayId: relay.objectID, url: relay.url ?? "", read: relay.read, write: relay.write)
            return addedSocket
        }
        return socket
    }
    
    var body: some View {
        VStack {
            ForEach(relays, id:\.objectID) { relay in
                RelayRowView(relay: relay, socket: socketForRelay(relay: relay))
                    .onTapGesture {
                        editRelay = relay
                    }
                Divider()
            }
        }
        .sheet(item: $editRelay, content: { relay in
            NavigationStack {
                RelayEditView(relay: relay, socket: socketForRelay(relay: relay))
            }
        })
    }    
}

struct RelaysView_Previews: PreviewProvider {
    static var previews: some View {
        
        let ns:NosturState = .shared
        
//        let cm = ConnectionManager()
//        var cm:SocketPool = .shared
        
        NavigationStack {
            RelaysView()
                .environment(\.managedObjectContext, EventsProvider.preview.container.viewContext)
                .environmentObject(ns)
//                .environmentObject(cm)
        }
    }
}
