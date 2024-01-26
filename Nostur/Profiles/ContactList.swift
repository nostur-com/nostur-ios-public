//
//  ContactList.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//


import SwiftUI

struct ContactList: View {
    @FetchRequest
    private var contacts: FetchedResults<Contact>
    private var pubkeys: [String]
    private var silent: [String]
    
    private var notInContacts: [String] {
        Array(Set(pubkeys).subtracting(Set(contacts.map { $0.pubkey })))
    }
    
    private var noMetadata: [String] {
        contacts
            .filter { $0.metadata_created_at == 0 }
            .map { $0.pubkey }
    }
    
    private var missing: [String] { notInContacts + noMetadata }

    init(pubkeys: [String], silent: [String]? = nil) {
        self.pubkeys = pubkeys
        self.silent = silent ?? []
        
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: true)],
            predicate: NSPredicate(format: "pubkey IN %@", pubkeys + self.silent),
            animation: .none)
    }
    
    var body: some View {
        ForEach(contacts) { contact in
            ProfileRow(contact: contact)
                .frame(height: 120)
//            Divider()
        }
        .onAppear {
            guard !missing.isEmpty else { return }
            L.og.info("Fetching \(missing.count) missing contacts")
            QueuedFetcher.shared.enqueue(pTags: missing)
        }
        .onDisappear {
            guard !missing.isEmpty else { return }
            QueuedFetcher.shared.dequeue(pTags: missing)
        }
        
        ForEach(noMetadata, id:\.self) { pubkey in
            ProfileRowMissing(pubkey: pubkey)
                .frame(height: 120)
//            Divider()
        }
    }
    
}

struct ContactList_Previews: PreviewProvider {
  
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            VStack {
                let pubkeys = [ "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","017903df5d1aa3c7497e40f6f423a7664ada998dfc77f0802ff3bd6e5c2e7625"]
                ContactList(pubkeys: pubkeys)
            }
        }
    }
}
