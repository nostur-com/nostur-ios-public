//
//  AccountsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI

struct AccountsView: View {
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var createAccountPresented = false
    @State var addReadOnlyAccountPresented = false
    
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Identity.createdAt, ascending: true)],
        animation: .default)
    private var identities: FetchedResults<Identity>
    
    var body: some View {
        let activeIdentities = identities.filter { $0.publicKey == activeAccountPublicKey }
        let inactiveIdentities = identities.filter { $0.publicKey != activeAccountPublicKey }
        
        VStack {
            
//            Button {
//                identities.forEach(viewContext.delete)
//                try! viewContext.save()
//            } label: {
//                Text("Delete all")
//            }
            
            if (identities.count == 0) {
                NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented)
            }
            else if (identities.count == 1) {
                List {
                    ForEach(identities, id: \.self) { identity in
                        NavigationLink(value: identity, label: {
                            Text(identity.name != "" ? identity.name : identity.publicKey ?? "(Unknown)")
                                .lineLimit(1)
                        })
                    }.onDelete(perform: deleteItems)
                }
                .navigationTitle("Accounts")
                .toolbar {
                    ToolbarItem {
                        Button {
                            createAccountPresented = true
                        } label: {
                            Label("Add account", systemImage: "plus")
                        }
                    }
                }
            }
            else {
                List {
                    
                    Section {
                        ForEach(activeIdentities, id: \.self) { identity in
                            NavigationLink(value:identity, label: {
                                Text(identity.name != "" ? identity.name : identity.publicKey ?? "(Unknown)")
                                    .lineLimit(1)
                            })
                        }
                    } header: {
                        Text("Main account")
                    }
                    
                    Section {
                        ForEach(inactiveIdentities, id: \.self) { identity in
                            NavigationLink(value:identity, label:{
                                Text(identity.name != "" ? identity.name : identity.publicKey ?? "(Unknown)")
                                    .lineLimit(1)
                            })
                        }.onDelete(perform: deleteItems)
                    } header: {
                        Text("Other accounts")
                    }
                }
                .navigationTitle("Accounts")
                .toolbar {
                    ToolbarItem {
                        Button {
                            createAccountPresented = true
                        } label: {
                            Label("Add account", systemImage: "plus")
                        }
                    }
                }
                
            }
        }
        .navigationDestination(isPresented: $createAccountPresented) {
            NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented)
        }
        .navigationDestination(isPresented: $addReadOnlyAccountPresented) {
            AddReadOnlyAccountView()
        }
        .navigationDestination(for: Identity.self) { identity in
            VStack {
                Text("Name: \(identity.name != "" ? identity.name : "(Unknown)")")
                Text("Priv: \(identity.privateKey ?? "(Unknown)")")
                Text("Pub: \(identity.publicKey ?? "(Unknown)")")
                
                AccountView(identity: identity)
                
                Button {
                    fetchContacts(identity:identity)
                } label: {
                    Text("Fetch contacts")
                }
                
                if activeAccountPublicKey != identity.publicKey {
                    Button {
                        activeAccountPublicKey = identity.publicKey ?? ""
                    } label: {
                        Text("Set as active account")
                    }
                }
            }
        }
        .onAppear {
            // Fetch identity metadata for accounts where who don't have the private key for
            
            let pubkeys = identities
                .filter { $0.privateKey == nil || $0.privateKey == "" }
                .map { $0.publicKey }
            
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
            
            ConnectionManager.shared.sendMessage(message)
            
//            print(msg)
        }
    }
    
    func fetchContacts(identity:Identity) {
        print(identity)
    }
    
    private func addItem() {
        withAnimation {
            let newItem = Identity(context: viewContext)
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
            offsets.map { identities[$0] }.forEach(viewContext.delete)
            
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

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView().environment(\.managedObjectContext,
                                    PersistenceController.preview.container.viewContext)
    }
}
