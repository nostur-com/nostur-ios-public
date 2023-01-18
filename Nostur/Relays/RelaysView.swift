//
//  RelaysView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI
import CoreData

struct RelaysView: View {
    
    @State var createRelayPresented = false
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Relay.createdAt, ascending: true)],
        animation: .default)
    
    private var relays: FetchedResults<Relay>
//    @State var selectedRelay:Relay?
    
    @ObservedObject var cm = ConnectionManager.shared
    
    var body: some View {
        List {
            ForEach(relays) { relay in
                NavigationLink(value: relay) {
                    HStack {
                        
                        if (cm.relaySockets.first { $0.relay == relay }?.isConnected ?? false) {
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
            
            }.onDelete(perform: deleteItems)
        }
        .navigationTitle("Relays")
        .onAppear {
            for socket in ConnectionManager.shared.relaySockets {
                if (socket.relay.read || socket.relay.write) && !socket.isConnected {
                    socket.socket.connect()
                }
            }
        }
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
            NewRelayView()
        }
    }
    
    private func addItem() {
        withAnimation {
            let newItem = Relay(context: viewContext)
            newItem.createdAt = Date()
            
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
        NavigationStack {
            RelaysView().environment(\.managedObjectContext,
                                      PersistenceController.preview.container.viewContext)
        }
    }
}
