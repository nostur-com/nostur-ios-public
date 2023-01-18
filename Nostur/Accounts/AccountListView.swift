//
//  AccountListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI

struct AccountListView: View {
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var createAccountPresented = false
    @State var addReadOnlyAccountPresented = false
    
    @EnvironmentObject var cm:ConnectionManager
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Identity.createdAt, ascending: true)],
        animation: .default)
    private var identities: FetchedResults<Identity>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    var body: some View {
    
        VStack {
//            Text("\(identities.count)")
            if (identities.count == 0) {
                NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented)
            }
            else {
                List {
                    
                    ForEach(identities, id: \.self) { identity in
                        NavigationLink(value:identity, label:{
                            HStack {
                                Text(identity.name != "" ? identity.name : identity.publicKey ?? "(Unknown)")
                                        .lineLimit(1)
                                if identity.publicKey == activeAccountPublicKey {
                                    Text("active")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .background(.green)
                                        .cornerRadius(5)
                                }
                            }
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
//                Text("Priv: \(identity.privateKey ?? "(Unknown)")")
                Text("Pub: \(identity.publicKey ?? "(Unknown)")")
                
                AccountView(identity: identity)
                
                Button {
                    fetchContacts(identity:identity)
                } label: {
                    Text("Fetch contacts")
                }
                Button {
                    updateContacts()
                } label: {
                    Text("Update contacts metadata")
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
            
            createAccountPresented = false
            addReadOnlyAccountPresented = false
            
            
            let pubkeys = identities
                .filter { $0.privateKey == nil || $0.privateKey == "" }
                .map { $0.publicKey }
            
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
            cm.sendMessage(message)
            
//            print(msg)
        }
    }
    
    func fetchContacts(identity:Identity) {
        if (identity.publicKey != nil) {
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: identity.publicKey!)))
        }
    }
    
    func updateContacts() { // move this method to somewhere more global maybe
        let pubkeys = contacts.map { $0.pubkey }
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
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

struct AccountListView_Previews: PreviewProvider {
    
//    static var viewContext = PersistenceController.preview.container.viewContext
    
    static var previews: some View {
        NavigationStack {
            AccountListView(activeAccountPublicKey: "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b")
                .environment(\.managedObjectContext,
                              PersistenceController.preview.container.viewContext)
        }
    }
}
