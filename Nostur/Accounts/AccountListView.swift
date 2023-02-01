//
//  AccountListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI

struct AccountListView: View {
    
//    let accountsRunLoop = Timer.publish(every: 2, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var fetching = true // fetching: true or, false if parsing
    @State var isViewDisplayed = false
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var createAccountPresented = false
    @State var addReadOnlyAccountPresented = false
    
    var ep: EventsProvider = .shared
    var cm: SocketPool = .shared
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
                    NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented) { name, about in
                        let newKeys = NKeys.newKeys()
                        
                        //        print("Private key: \(privateKeyHex)") for testing. dont print this ever
                        print("Public key: \(newKeys.publicKeyHex())")
                        
                        let account = Account(context: viewContext)
                        account.id = UUID()
                        account.createdAt = Date()
                        account.name = name
                        account.about = about
                        account.privateKey = newKeys.privateKeyHex()
                        account.publicKey = newKeys.publicKeyHex()
                        
                        do {
                            try viewContext.save()
                            activeAccountPublicKey = newKeys.publicKeyHex()
                        } catch {
                            // Replace this implementation with code to handle the error appropriately.
                            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                            let nsError = error as NSError
                            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                        }
                    }
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
                                            .padding(.horizontal, 10)
                                            .background(Color("OrangeColor"))
                                            .cornerRadius(8)
                                    }
                                    if account.privateKey == nil {
                                        Text("read only")
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .background(Color.red)
                                            .cornerRadius(8)
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
                NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented) { name, about in
                    let newKeys = NKeys.newKeys()
                    
                    //        print("Private key: \(privateKeyHex)") for testing. dont print this ever
                    print("Public key: \(newKeys.publicKeyHex())")
                    
                    let account = Account(context: viewContext)
                    account.id = UUID()
                    account.createdAt = Date()
                    account.name = name
                    account.about = about
                    account.privateKey = newKeys.privateKeyHex()
                    account.publicKey = newKeys.publicKeyHex()
                    
                    do {
                        try viewContext.save()
                        activeAccountPublicKey = newKeys.publicKeyHex()
                    } catch {
                        // Replace this implementation with code to handle the error appropriately.
                        // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                        let nsError = error as NSError
                        fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                    }
                }
            }
            .navigationDestination(isPresented: $addReadOnlyAccountPresented) {
                AddReadOnlyAccountView { pubkey in
                    let account = Account(context: viewContext)
                    account.id = UUID()
                    account.createdAt = Date()
                    // TODO: Check if valid pubkey before save.
                    // Convert npub to hex... etc
                    account.publicKey = pubkey
                    
                    do {
                        try viewContext.save()
                        activeAccountPublicKey = pubkey
                    } catch {
                        let nsError = error as NSError
                        fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                    }
                }
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
                if (pubkeys.count > 0) {
                    let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
                    cm.sendMessage(message)
                }
            }
            .onAppear {
                self.isViewDisplayed = true
            }
            .onDisappear {
                self.isViewDisplayed = false
            }
    //        .onReceive(accountsRunLoop) { time in
    //
    //            if (!isViewDisplayed) {
    //                return
    //            }
    //
    //            if (fetching) { // fetching
    //                print("🍭🍭🍭 GONNA FETCH BABY 🍭🍭🍭🍭")
    //                let pubkeys = accounts
    //                    .filter { $0.privateKey == nil || $0.privateKey == "" }
    //                    .map { $0.publicKey }
    //
    //                let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
    //                cm.sendMessage(message)
    //            }
    //            else { // parsing
    ////                Task {
    //////                    let before = ep.queue.count
    ////                    let before = await ep.queue.count
    ////                    try await ep.importEvents()
    ////                    if (before != 0) {
    //////                        print("didParse? queue count, before: \(before) after: \(ep.queue.count)")
    ////                        print("didParse? queue count, before: \(before) after: \(await ep.queue.count)")
    ////                    }
    ////                }
    //            }
    //
    //            fetching = !fetching
    //        }
        
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
    static var previews: some View {
        NavigationStack {
            AccountListView()
                .withPreviewEnvironment()
        }
    }
}
