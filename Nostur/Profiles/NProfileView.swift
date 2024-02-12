//
//  NProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/05/2023.
//

import SwiftUI

struct NProfileView: View {
    
    let identifier:ShareableIdentifier
    
    var body: some View {
        if let pubkey = identifier.pubkey {
            NProfileViewInner(predicate: NSPredicate(format: "pubkey == %@", pubkey), identifier: identifier)
        }
    }
    
    struct NProfileViewInner: View {
        
        @State var nrPost:NRPost?
        @State var fetchTask:Task<Void, Never>?
        
        private var fetchRequest: FetchRequest<Contact>
        private var contacts: FetchedResults<Contact> {
            fetchRequest.wrappedValue
        }
        private var identifier:ShareableIdentifier
        
        init(predicate: NSPredicate, identifier:ShareableIdentifier) {
            fetchRequest = FetchRequest(
                sortDescriptors: [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: false)],
                predicate: predicate
            )
            self.identifier = identifier
        }
        
        var body: some View {
            VStack {
                if let contact = contacts.first {
                    ProfileRow(contact: contact)
                }
                else {
                    ProgressView()
                        .hCentered()
                        .onAppear {
                            guard let pubkey = identifier.pubkey else {
                                L.og.debug("\(identifier.bech32string) has no pubkey")
                                return
                            }
                            L.og.debug("🟢 Fetching for NEventView \(pubkey) / \(identifier.bech32string)")
                            req(RM.getUserMetadata(pubkey: pubkey))
                            
                            if !identifier.relays.isEmpty {
                                fetchTask = Task {
                                    do {
                                        try await Task.sleep(nanoseconds: UInt64(3 * Double(NSEC_PER_SEC)))
                                        let ctx = bg()
                                        await ctx.perform {
                                            // If we don't have the event after X seconds, fetch from relay hint
                                            if Contact.fetchByPubkey(pubkey, context: ctx) == nil {
                                                if let relay = identifier.relays.first {
                                                    ConnectionPool.shared.sendEphemeralMessage(
                                                        RM.getUserMetadata(pubkey: pubkey),
                                                        relay: relay
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    catch { }
                                }
                            }
                        }
                        .onDisappear {
                            if let task = fetchTask {
                                task.cancel()
                            }
                        }
                        .frame(minHeight: 200)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.regularMaterial, lineWidth: 1)
            )
        }
    }
}

import NavigationBackport

struct NProfileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NBNavigationStack {
                if let identifier = try? ShareableIdentifier("nprofile1qqs80w7ryyy8jpwe372phkw5e3xjs4hacre0pqln4ct8238p5weeaygm0c3wt") {
                    NProfileView(identifier: identifier)
                }
            }
        }        
    }
}
