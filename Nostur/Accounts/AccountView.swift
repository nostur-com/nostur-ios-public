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
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var identity: Identity
    @State var newPrivateKey = ""
    
    let persistenceController = PersistenceController.shared
    
    var body: some View {
        
        let shouldDisable = identity.privateKey == nil || identity.privateKey == ""
        
        VStack {
            
            Text("Following \(identity.follows?.count ?? 0)")
            
            Form {
//            List {
              
                Section(header: Text("Your name") ) {
                    TextField("Enter your name", text: $identity.name).disabled(shouldDisable)
                }
                
                Section(header: Text("Bio") ) {
                    TextField("Something about yourself", text:$identity.about).disabled(shouldDisable)
                }

                Section(header: Text("NIP-05 identifier") ) {
                    TextField("", text: $identity.nip05).keyboardType(.emailAddress).disabled(shouldDisable)
                }

                Section(header: Text("Lightning Address (LUD-16)") ) {
                    TextField("", text: $identity.lud16).keyboardType(.emailAddress).disabled(shouldDisable)
                }

                Section(header: Text("Profile picturel URL") ) {
                    TextField("https://nostur.com/profile.jpg", text: $identity.picture).keyboardType(.URL).disabled(shouldDisable)
                }
                
                if (shouldDisable) {
                    Section(header:Text("Import private key")) {
                        TextField("hex", text: $newPrivateKey).foregroundColor(.primary)
                    }.foregroundColor(.primary)
                }
            }.foregroundColor(.gray)
            Button {
                if newPrivateKey != "" {
                    identity.privateKey = newPrivateKey
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
        }.onAppear {
            
            print(identity.privateKey ?? "")
            print(identity.publicKey ?? "")
            
            let fetchRequest = NSFetchRequest<Event>(entityName: "Event")
          //  fetchRequest = Event.fetchRequest()

            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Event.created_at, ascending: false)
            ]
            
            fetchRequest.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    NSPredicate(
                        format: "pubkey = %@", identity.publicKey!
                    ),
                    NSPredicate(
                        format: "kind = %i", 0
                    )
                ]
            )
            
//            fetchRequest.predicate = NSPredicate(
//                format: "kind = %i", 0
//            )
            let objects = try! persistenceController.containerLocal.viewContext.fetch(fetchRequest)
            print("🉐🉐🉐🉐")

            if let event = objects.first {
                let content = JSON(event.content)
                if let dataFromString = content.stringValue.data(using: .utf8, allowLossyConversion: false) {
                    let json = try! JSON(data: dataFromString)
                    print(json["nip05"].stringValue)
                    
                    identity.name = json["name"].stringValue
                    identity.about = json["about"].stringValue
                    identity.picture = json["picture"].stringValue
                    identity.nip05 = json["nip05"].stringValue
                    identity.lud16 = json["lud16"].stringValue
                    
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

    func saveAccount() throws {
        try! viewContext.save()


        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: identity.name, about: identity.about, picture: identity.picture)
        if identity.nip05 != "" { setMetadataContent.nip05 = identity.nip05 }
        if identity.lud16 != "" { setMetadataContent.lud16 = identity.lud16 }

        guard identity.privateKey != nil else {
            throw "Identity has no private key"
        }

        let keys = NKeys(privateKeyHex: identity.privateKey!)

        var event = NEvent(content: setMetadataContent)
        event = try! event.sign(keys)

        print(event.eventJson())
        print(event.wrappedEventJson())

        // broadcast to relays
        ConnectionManager.shared.sendMessage(text: event.wrappedEventJson())
    }
}

struct AccountView_Previews: PreviewProvider {
    
    static var viewContext = PersistenceController.preview.container.viewContext

    static var previews: some View {
        
        // Create a fetch request with a string filter
        // for an entity’s name
//        let fetchRequest: NSFetchRequest<Identity>
//        fetchRequest = Identity.fetchRequest()

//        fetchRequest.predicate = NSPredicate(
//            format: "name LIKE %@", "Robert"
//        )


        // Perform the fetch request to get the objects
        // matching the predicate
//        let identity = try! viewContext.fetch(fetchRequest).first
        
        let identity = Identity(context: viewContext)
        identity.createdAt = Date()
        identity.id = UUID()
        //identity.privateKey = "184a90b0cbdf4b4a318d33f6464593d9936430c6793fed82d9b6ec3b8f12804f"
        identity.publicKey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        identity.name = "Eltje"
        identity.about = "Test"
        
        return AccountView(identity: identity)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
