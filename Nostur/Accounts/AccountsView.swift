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
    
    @EnvironmentObject var cm:ConnectionManager
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)],
        animation: .default)
    private var identities: FetchedResults<Account>
    
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
                    ForEach(identities, id: \.self) { account in
                        NavigationLink(value: account, label: {
                            Text(account.name != "" ? account.name : account.publicKey ?? "(Unknown)")
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
                        ForEach(activeIdentities, id: \.self) { account in
                            NavigationLink(value:account, label: {
                                Text(account.name != "" ? account.name : account.publicKey ?? "(Unknown)")
                                    .lineLimit(1)
                            })
                        }
                    } header: {
                        Text("Main account")
                    }
                    
                    Section {
                        ForEach(inactiveIdentities, id: \.self) { account in
                            NavigationLink(value:account, label:{
                                Text(account.name != "" ? account.name : account.publicKey ?? "(Unknown)")
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
        .navigationDestination(for: Account.self) { account in
            VStack {
                Text("Name: \(account.name != "" ? account.name : "(Unknown)")")
                Text("Priv: \(account.privateKey ?? "(Unknown)")")
                Text("Pub: \(account.publicKey ?? "(Unknown)")")
                
                AccountView(account: account)
                
                Button {
                    fetchContacts(account:account)
                } label: {
                    Text("Fetch contacts")
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
            
            let pubkeys = identities
                .filter { $0.privateKey == nil || $0.privateKey == "" }
                .map { $0.publicKey }
            
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
            
            cm.sendMessage(message)
            
//            print(msg)
        }
    }
    
    func fetchContacts(account:Account) {
        print(account)
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
