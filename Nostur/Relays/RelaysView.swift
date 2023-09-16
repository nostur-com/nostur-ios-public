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
    @ObservedObject var sp:SocketPool = .shared
    
    var isConnected:Bool {
        socket?.isConnected ?? false
    }
    
    var socket:NewManagedClient? {
        sp.sockets.first(where: { $0.key == relay.objectID.uriRepresentation().absoluteString } )?.value
    }
    
    var body: some View {
        HStack {
            
            if (isConnected) {
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
                    socket?.read = relay.read
                    DataProvider.shared().save()
                }
            
            Image(systemName:"arrow.up.circle.fill").foregroundColor(relay.write ? .green : .gray)
                .opacity(relay.write ? 1.0 : 0.2)
                .onTapGesture {
                    relay.write.toggle()
                    socket?.write = relay.write
                    DataProvider.shared().save()
                }
        }
    }
}

struct RelaysView: View {
    @EnvironmentObject var theme:Theme
    @State var createRelayPresented = false
    @State var editRelay:Relay?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Relay.createdAt, order: .forward)],
        animation: .default)
    var relays: FetchedResults<Relay>

    @ObservedObject var sp:SocketPool = .shared

    func socketForRelay(relay: Relay) -> NewManagedClient {
        guard let socket = sp.sockets[relay.objectID.uriRepresentation().absoluteString] else {
            let addedSocket = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relay.url ?? "wss://localhost:123456/invalid_relay_url", read: relay.read, write: relay.write, excludedPubkeys: relay.excludedPubkeys)
            return addedSocket
        }
        return socket
    }
    
    var body: some View {
        VStack {
            ForEach(relays, id:\.objectID) { relay in
                RelayRowView(relay: relay)
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
            .presentationBackground(theme.background)
        })
    }    
}

struct RelaysView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadRelays()
        }) {
            NavigationStack {
                RelaysView()
                    .padding()
            }
        }
    }
}
