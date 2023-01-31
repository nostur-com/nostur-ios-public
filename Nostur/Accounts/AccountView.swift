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
    
//    @EnvironmentObject var cm:ConnectionManager
    var cm:SocketPool = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var account: Account
    @State var newPrivateKey = ""
    @State var searchText = ""
    
    let persistenceController = EventsProvider.shared
    
    var body: some View {
        
        let shouldDisable = account.privateKey == nil || account.privateKey == ""
        
        ScrollView {
            VStack {
                
                Text("Following \(account.follows?.count ?? 0)")
                
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
                .foregroundColor(.gray)
                
                VStack {
                    ForEach(Array(account.follows?.filter({ contact in
                        if (searchText == "") { return true }
                        if contact.authorName.contains(searchText) {
                            return true
                        }
                        if contact.username.contains(searchText) {
                            return true
                        }
                        if contact.about != nil && contact.about!.contains(searchText) {
                            return true
                        }
                        return false
                    }) ?? [])) { contact in
                        ProfileRow(contact: contact)
                    }
                }.searchable(text: $searchText)
 
            }
            .onAppear {
                
                print(account.privateKey ?? "")
                print(account.publicKey ?? "")
                
                let fetchRequest = NSFetchRequest<Event>(entityName: "Event")

                fetchRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \Event.created_at, ascending: false)
                ]
                
                fetchRequest.predicate = NSCompoundPredicate(
                    andPredicateWithSubpredicates: [
                        NSPredicate(
                            format: "pubkey = %@", account.publicKey!
                        ),
                        NSPredicate(
                            format: "kind = %i", 0
                        )
                    ]
                )
                
                let objects = try! persistenceController.container.viewContext.fetch(fetchRequest)
                print("🉐🉐🉐🉐")

                if let event = objects.first {
                    let content = JSON(event.content!)
                    if let dataFromString = content.stringValue.data(using: .utf8, allowLossyConversion: false) {
                        let json = try! JSON(data: dataFromString)
                        print(json["nip05"].stringValue)
                        
                        account.name = json["name"].stringValue
                        account.about = json["about"].stringValue
                        account.picture = json["picture"].stringValue
                        account.nip05 = json["nip05"].stringValue
                        account.lud16 = json["lud16"].stringValue
                        
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
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if newPrivateKey != "" {
                    account.privateKey = newPrivateKey
                }
                try! saveAccount()
                dismiss()
            } label: {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 220, height: 50)
                    .background(.cyan)
                    .cornerRadius(15.0)
            }
        }.background(.regularMaterial)
            
    }

    func saveAccount() throws {
        try! viewContext.save()


        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }

//        guard account.privateKey != nil else {
//            throw "Account has no private key"
//        }

        
        if (account.privateKey != nil) {
            let keys = NKeys(privateKeyHex: account.privateKey!)

            var event = NEvent(content: setMetadataContent)
            event = try! event.sign(keys)

            print(event.eventJson())
            print(event.wrappedEventJson())

            // broadcast to relays
            let message = ClientMessage(type: .EVENT, message: event.wrappedEventJson())
            cm.sendMessage(message)
        }
    }
}

struct AccountView_Previews: PreviewProvider {
    
    static var viewContext = EventsProvider.preview.container.viewContext

    static var previews: some View {
        
        // Create a fetch request with a string filter
        // for an entity’s name
//        let fetchRequest: NSFetchRequest<Account>
//        fetchRequest = Account.fetchRequest()

//        fetchRequest.predicate = NSPredicate(
//            format: "name LIKE %@", "Robert"
//        )


        // Perform the fetch request to get the objects
        // matching the predicate
//        let account = try! viewContext.fetch(fetchRequest).first
        
        let account = Account(context: viewContext)
        account.createdAt = Date()
        account.id = UUID()
        //account.privateKey = "184a90b0cbdf4b4a318d33f6464593d9936430c6793fed82d9b6ec3b8f12804f"
        account.publicKey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        account.name = "Eltje"
        account.about = "Test"
        
        return AccountView(account: account)
            .withPreviewEnvironment()
    }
}
