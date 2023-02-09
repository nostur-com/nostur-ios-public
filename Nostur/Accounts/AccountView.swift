//
//  AccountView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI
import CoreData
import SwiftyJSON

struct AccountView: View {
    
    var sp:SocketPool = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var account: Account
    @State var newPrivateKey = ""
    @State var contactsPresented = false
    
    var body: some View {
        let shouldDisable = account.privateKey == nil || account.privateKey == ""
        VStack {
            Button { contactsPresented = true } label: {
                
                
                NavigationLink(value: ViewPath.Following(account:account)) {
                    Text("Following \(account.follows?.count ?? 0)")
                }
                
                
            }
            
            Form {
                Section(header: Text("Your name") ) {
                    TextField("Enter your name", text: $account.name).disabled(shouldDisable)
                }
                
                Section(header: Text("Bio") ) {
                    TextField("Something about yourself", text:$account.about).disabled(shouldDisable)
                }
                
                Section(header: Text("NIP-05 identifier") ) {
                    TextField("", text: $account.nip05).keyboardType(.emailAddress).disabled(shouldDisable)
                }
                
                Section(header: Text("Lightning Address (LUD-16)") ) {
                    TextField("", text: $account.lud16).keyboardType(.emailAddress).disabled(shouldDisable)
                }
                
                Section(header: Text("Profile picturel URL") ) {
                    TextField("https://nostur.com/profile.jpg", text: $account.picture).keyboardType(.URL).disabled(shouldDisable)
                }
                
                if (shouldDisable) {
                    Section(header:Text("Import private key")) {
                        TextField("hex", text: $newPrivateKey).foregroundColor(.primary)
                    }.foregroundColor(.primary)
                }
                
                Section(header: Text("Public key") ) {
                    Text(account.npub)
                }
            }
            .foregroundColor(shouldDisable ? .gray : .primary)
            
        }
        .onAppear {
            preloadFromEvent()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if newPrivateKey != "" { // TODO: Handle nsec format
                    account.privateKey = newPrivateKey
                }
                do {
                    try viewContext.save()
                    try publishMetadataEvent(account: account, sp: sp, context: viewContext)
                    dismiss()
                }
                catch {
                    print("Error saving account")
                }
            } label: {
                Text("Save").frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
        }
        .background(.regularMaterial)
        .navigationDestination(isPresented: $contactsPresented) {
            AccountFollowingList(account: account)
        }
    }
}

extension AccountView {
    func saveAccount() throws {
        
    }
    
    // TODO: MOVE TO Event Publisher class
    func publishMetadataEvent(account:Account, sp:SocketPool, context:NSManagedObjectContext) throws {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }
        
        if (account.privateKey != nil) {
            let keys = NKeys(privateKeyHex: account.privateKey!)
            
            var event = NEvent(content: setMetadataContent)
            do {
                event = try event.sign(keys)
                
                print(event.eventJson())
                print(event.wrappedEventJson())
                
                _ = Event.saveEvent(event: event, context: context)
                try context.save()
                
                // broadcast to relays
                let message = ClientMessage(type: .EVENT, message: event.wrappedEventJson())
                sp.sendMessage(message)
            }
            catch {
                print("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
            }
        }
    }
    
    func preloadFromEvent() {
        let fr = NSFetchRequest<Event>(entityName: "Event")
        fr.predicate = NSPredicate(format: "pubkey = %@ AND kind == 0", account.publicKey!)
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        print("preload...")
        if let event = try? viewContext.fetch(fr).first {
            print("\(event.content ?? "??")")
            if let metadata = try? event.getMetadataContent() {
                account.name = metadata.name ?? ""
                account.about = metadata.about ?? ""
                account.picture = metadata.picture ?? ""
                account.banner = metadata.banner ?? ""
                account.nip05 = metadata.nip05 ?? ""
                account.lud16 = metadata.lud16 ?? ""
                
                do {
                    try viewContext.save()
                } catch {
                    print("error saving own account data from event to account")
                }
            }
        }
    }
}



struct AccountView_Previews: PreviewProvider {
    static var previews: some View {
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
            NavigationStack {
                AccountView(account: account!)
                    .withPreviewEnvironment()
            }
    }
}
