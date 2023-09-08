//
//  ProfileByPubkey.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

struct ProfileByPubkey: View {
    @EnvironmentObject var theme:Theme
    let sp:SocketPool = .shared
    @EnvironmentObject var ns:NosturState
     
    
    var pubkey:String
    var tab:String?
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
    let timeOut = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    
    @State var editingAccount:Account?
    
    init(pubkey:String, tab:String? = nil) {
        self.pubkey = pubkey
        self.tab = tab
        
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
    }
    
    var body: some View {
        if let contact = contacts.first {
            ProfileView(contact: contact, tab:tab)
        }
        else {
            ProgressView().onAppear {
                L.og.info("🟢 ProfileByPubkey.onAppear no contact so REQ.0: \(pubkey)")
                req(RM.getUserMetadata(pubkey: pubkey))
            }
            .sheet(item: $editingAccount) { account in
                NavigationStack {
                    AccountEditView(account: account)
                }
                .presentationBackground(theme.background)
            }
            .onReceive(timeOut) { firedDate in
                timeOut.upstream.connect().cancel()
                if ns.account?.publicKey == pubkey {
                    editingAccount = ns.account!
                }
            }
        }
    }
}

struct ProfileByPubkey_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            ProfileByPubkey(pubkey: "77bbc321087905d98f941bd9d4cc4d2856fdc0f2f083f3ae167544e1a3b39e91")
        }
    }
}
