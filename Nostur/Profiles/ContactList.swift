//
//  ContactList.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ContactList: View {
    
    let sp:SocketPool = .shared
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    var pubkeys:[String]
    var silent:[String]
    
    var notInContacts:[String] {
        Array(Set(pubkeys).subtracting(Set(contacts.map { $0.pubkey })))
    }
    
    var noMetadata:[String] {
        contacts
            .filter { $0.metadata_created_at == 0 }
            .map { $0.pubkey }
    }
    
    var missing:[String] { notInContacts + noMetadata }

    init(pubkeys:[String], silent:[String]? = nil) {
        self.pubkeys = pubkeys
        self.silent = silent ?? []
        
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: true)],
            predicate: NSPredicate(format: "pubkey IN %@", pubkeys + self.silent),
            animation: .none)
    }
    
    var body: some View {
        VStack {
            Text("Total: \(pubkeys.count)\(silent.count > 0 ? " + \(silent.count) silent/private" : "")")
            LazyVStack {
                ForEach(contacts) { contact in
                    ProfileRow(contact: contact)
                        .frame(height: 120)
                    Divider()
                }
            }
            
            VStack {
                ForEach(noMetadata, id:\.self) { pubkey in
                    ProfileRowMissing(pubkey: pubkey)
                        .frame(height: 120)
                    Divider()
                }
            }
            
        }
        .onAppear {
            guard missing.count != 0 else { return }
            print("Fetching \(missing.count) missing contacts")
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missing)))
            
            // TODO: ADD FETCH NEW CONTACT INFO ON APPEAR, SIMILAR TO REQUESTFORLATEST ON LISTVIEW
        }
    }
    
}

struct ContactList_Previews: PreviewProvider {
  
    static var previews: some View {
        VStack {
            
            let pubkeys = ["5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","017903df5d1aa3c7497e40f6f423a7664ada998dfc77f0802ff3bd6e5c2e7625"]
            
            ContactList(pubkeys: pubkeys)
                .withPreviewEnvironment()
            
        }
    }
}
