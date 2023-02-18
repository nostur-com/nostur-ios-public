////
////  AccountListView.swift
////  Nostur
////
////  Created by Fabian Lachman on 10/01/2023.
////
//
//import SwiftUI
//
//struct AccountListView: View {
//    
//    @EnvironmentObject var ns:NosturState
//    @State var fetching = true // fetching: true or, false if parsing
//    @State var isViewDisplayed = false
//    
//    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
//    @State var createAccountPresented = false
//    @State var addReadOnlyAccountPresented = false
//    
//    var ep: EventsProvider = .shared
//    var sp: SocketPool = .shared
//    @Environment(\.managedObjectContext) var viewContext
//    
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)],
//        animation: .default)
//    private var accounts: FetchedResults<Account>
//    
//    var body: some View {
//        
//            VStack {
//                Text("Accounts").font(.title3)
//                if (accounts.count == 0) {
//                    NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented) { name, about in
//                        
//                        let newAccount = AccountManager.shared.generateAccount(name: name, about: about, context: viewContext)
//                        activeAccountPublicKey = newAccount.publicKey!
//                        do {
//                            let _ = try ns.loadActiveAccount(account: newAccount)
//                        }
//                        catch {
//                            print("🔴🔴 could not ns.loadActiveAccount")
//                            print(error)
//                        }
//                    }
//                }
//                else {
//                    List {
//                        ForEach(accounts, id: \.self) { account in
//                            NavigationLink(value:account, label: {
//                                HStack {
//                                    Text(account.name != "" ? account.name : account.publicKey ?? "(Unknown)")
//                                        .lineLimit(1)
//                                    if account.publicKey == activeAccountPublicKey {
//                                        Text("active")
//                                            .foregroundColor(.white)
//                                            .padding(.horizontal, 10)
//                                            .background(Color("OrangeColor"))
//                                            .cornerRadius(8)
//                                    }
//                                    if account.privateKey == nil {
//                                        Text("read only")
//                                            .foregroundColor(.white)
//                                            .padding(.horizontal, 10)
//                                            .background(Color.red)
//                                            .cornerRadius(8)
//                                    }
//                                }
//                            })
//                        }.onDelete(perform: deleteItems)
//                    }
//                    .navigationTitle("Accounts")
//                    .toolbar {
//                        ToolbarItem {
//                            Button {
//                                createAccountPresented = true
//                            } label: {
//                                Label("Add account", systemImage: "plus")
//                            }
//                        }
//                    }
//                }
//            }
//            .navigationDestination(isPresented: $createAccountPresented) {
//                NewAccountView(addReadOnlyAccountPresented: $addReadOnlyAccountPresented) { name, about in
//                    let newAccount = AccountManager.shared.generateAccount(name: name, about: about, context: viewContext)
//                    activeAccountPublicKey = newAccount.publicKey!
//                    do {
//                        let _ = try ns.loadActiveAccount(account: newAccount)
//                    }
//                    catch {
//                        print("🔴🔴 could not ns.loadActiveAccount")
//                        print(error)
//                    }
//                }
//            }
//            .navigationDestination(isPresented: $addReadOnlyAccountPresented) {
//                AddReadOnlyAccountView { pubkey in
//                    ns.pendingFirstContactsFetch = true
//                    let account = Account(context: viewContext)
//                    account.id = UUID()
//                    account.createdAt = Date()
//                    // TODO: Check if valid pubkey before save.
//                    // Convert npub to hex... etc
//                    account.publicKey = pubkey
//                    
//                    // 1. Prefill from cached event
//                    Account.preFillReadOnlyAccountInfo(account: account, context: viewContext)
//                    Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
//                    
//                    do {
//                        try viewContext.save()
//                        activeAccountPublicKey = pubkey
//                        try _ = ns.loadActiveAccount(account: account)
//                        
//                        
//                        // 2. But also check if there are newer events
//                        let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: pubkey))
//                        sp.sendMessage(message)
//                    } catch {
//                        let nsError = error as NSError
//                        fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//                    }
//                }
//            }
//            .navigationDestination(for: Account.self) { account in
//                AccountEditView(account: account)
//            }
//            .onAppear {
//                // Fetch account metadata for accounts where who don't have the private key for
//                
////                createAccountPresented = false
////                addReadOnlyAccountPresented = false
////                
////                
////                let pubkeys = accounts
////                    .filter { $0.privateKey == nil || $0.privateKey == "" }
////                    .map { $0.publicKey! }
////                if (pubkeys.count > 0) {
////                    let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
////                    sp.sendMessage(message)
////                }
//            }
//            .onAppear {
//                self.isViewDisplayed = true
//            }
//            .onDisappear {
//                self.isViewDisplayed = false
//            }
//    //        .onReceive(accountsRunLoop) { time in
//    //
//    //            if (!isViewDisplayed) {
//    //                return
//    //            }
//    //
//    //            if (fetching) { // fetching
//    //                print("🍭🍭🍭 GONNA FETCH BABY 🍭🍭🍭🍭")
//    //                let pubkeys = accounts
//    //                    .filter { $0.privateKey == nil || $0.privateKey == "" }
//    //                    .map { $0.publicKey }
//    //
//    //                let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys))
//    //                cm.sendMessage(message)
//    //            }
//    //            else { // parsing
//    ////                Task {
//    //////                    let before = ep.queue.count
//    ////                    let before = await ep.queue.count
//    ////                    try await ep.importEvents()
//    ////                    if (before != 0) {
//    //////                        print("didParse? queue count, before: \(before) after: \(ep.queue.count)")
//    ////                        print("didParse? queue count, before: \(before) after: \(await ep.queue.count)")
//    ////                    }
//    ////                }
//    //            }
//    //
//    //            fetching = !fetching
//    //        }
//        
//    }
//    
//    private func addItem() {
//        withAnimation {
//            let newItem = Account(context: viewContext)
//            newItem.createdAt = Date()
//            
//            do {
//                try viewContext.save()
//            } catch {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                let nsError = error as NSError
//                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//            }
//        }
//    }
//    
//    private func deleteItems(offsets: IndexSet) {
//        withAnimation {
//            offsets.map {
//                if (accounts[$0] == ns.account) {
//                    ns.setAccount()
//                }
//                AccountManager.shared.deletePrivateKey(forPublicKeyHex: accounts[$0].publicKey!
//                )
//                return accounts[$0]
//            }.forEach(viewContext.delete)
//            ns.objectWillChange.send()
//            do {
//                try viewContext.save()
//            } catch {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                let nsError = error as NSError
//                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//            }
//        }
//    }
//}
//
//struct AccountListView_Previews: PreviewProvider {
//    static var previews: some View {
//        NavigationStack {
//            AccountListView()
//                .withPreviewEnvironment()
//        }
//    }
//}
