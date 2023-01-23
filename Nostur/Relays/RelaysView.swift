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
    
    var body: some View {
        HStack {
            
            if (relay.isConnected) {
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
            
            Image(systemName:"arrow.up.circle.fill").foregroundColor(relay.write ? .green : .gray)
                .opacity(relay.write ? 1.0 : 0.2)
        }
    }
}

struct RelaysView: View {
    
    @State var createRelayPresented = false
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Relay.createdAt, order: .forward)],
        animation: .default)
    var relays: FetchedResults<Relay>
    
    @EnvironmentObject var cm:ConnectionManager
    
    var body: some View {
        List {
            ForEach(relays, id:\.objectID) { relay in
                NavigationLink(value: relay) {
                    RelayRowView(relay: relay)
                }
                
            }.onDelete(perform: deleteItems)
        }
        .onAppear {
            for socket in cm.relaySockets {
                if (socket.relay.read || socket.relay.write) && !socket.relay.isConnected {
                    socket.socket.connect()
                }
            }
        }
        .navigationTitle("Relays")
        .toolbar {
            ToolbarItem {
                Button {
                    createRelayPresented = true
                } label: {
                    Label("Add relay", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Relay.self) { relay in
            RelayEditView(relay: relay)
        }
        .navigationDestination(isPresented: $createRelayPresented) {
            NewRelayView { url in
                let relay = Relay(context: viewContext)
                relay.id = UUID()
                relay.createdAt = Date()
                relay.url = url
                
                do {
                    try viewContext.save()
                    let relaySocket = RelaySocket(relay: relay, delegate: cm.eventReceivingDelegate)
                    print("🟣🟣 connecting to \(relay.url ?? "?")")
                    relaySocket.connect()
                    cm.relaySockets.append(relaySocket)
                } catch {
                    // Replace this implementation with code to handle the error appropriately.
                    // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { relays[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
}

struct RelaysView_Previews: PreviewProvider {
    static var previews: some View {
        
        let cm = ConnectionManager()
        
        NavigationStack {
            RelaysView().environment(\.managedObjectContext,
                                      EventsProvider.preview.container.viewContext)
            .environmentObject(cm)
        }
    }
}
