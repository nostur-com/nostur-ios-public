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
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)],
        animation: .default)
    private var accounts: FetchedResults<Account>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    var body: some View {
    
        VStack {
//            Text("\(identities.count)")
            if (accounts.count == 0) {
                NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented)
            }
            else {
                List {
                    
                    ForEach(accounts, id: \.self) { account in
                        NavigationLink(value:account, label:{
                            HStack {
                                Text(account.name != "" ? account.name : account.publicKey ?? "(Unknown)")
                                        .lineLimit(1)
                                if account.publicKey == activeAccountPublicKey {
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
        .navigationDestination(for: Account.self) { account in
            VStack {
                Text("Name: \(account.name != "" ? account.name : "(Unknown)")")
//                Text("Priv: \(account.privateKey ?? "(Unknown)")")
                Text("Pub: \(account.publicKey ?? "(Unknown)")")
                
                AccountView(account: account)
                
                Button {
                    fetchContacts(account:account)
                } label: {
                    Text("Fetch contacts")
                }
                Button {
                    updateContacts()
                } label: {
                    Text("Update contacts metadata")
                }
                
                if activeAccountPublicKey != account.publicKey {
                    Button {
                        activeAccountPublicKey = account.publicKey ?? ""
                    } label: {
                        Text("Set as active account")
                    }
                }
            }
        }
        .onAppear {
            // Fetch account metadata for accounts where who don't have the private key for
            
            createAccountPresented = false
            addReadOnlyAccountPresented = false
            
            
            let pubkeys = accounts
                .filter { $0.privateKey == nil || $0.privateKey == "" }
                .map { $0.publicKey }
            
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
            cm.sendMessage(message)
            
//            print(msg)
        }
    }
    
    func fetchContacts(account:Account) {
        if (account.publicKey != nil) {
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: account.publicKey!)))
        }
    }
    
    func updateContacts() { // move this method to somewhere more global maybe
        let pubkeys = contacts.map { $0.pubkey }
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
    }
    
    private func addItem() {
        withAnimation {
            let newItem = Account(context: viewContext)
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
            offsets.map { accounts[$0] }.forEach(viewContext.delete)
            
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
        
        let accountState = AccountState(viewContext: PersistenceController.preview.container.viewContext)
        
        let cm = ConnectionManager()
        
        NavigationStack {
            AccountListView(activeAccountPublicKey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0")
                .environment(\.managedObjectContext,
                              PersistenceController.preview.container.viewContext)
                .environmentObject(accountState)
                .environmentObject(cm)
        }
    }
}
