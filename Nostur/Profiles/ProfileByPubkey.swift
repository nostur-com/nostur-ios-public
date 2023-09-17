//
//  ProfileByPubkey.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

struct ProfileByPubkey: View {
    @EnvironmentObject private var theme:Theme
    
    let pubkey:String
    var tab:String?
        
    @State private var editingAccount:Account? = nil
    @StateObject private var vm = FetchVM<NRContact>()

    var body: some View {
        switch vm.state {
        case .initializing:
            ProgressView()
                .onAppear {
                    vm.setFetchParams((
                        req: {
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
                                    let nrContact = NRContact(contact: contact, following: NosturState.shared.bgFollowingPublicKeys.contains(pubkey))
                                    vm.ready(nrContact) // 2A. DONE
                                }
                                else { req(RM.getUserMetadata(pubkey: pubkey)) } // 2B. FETCH IF WE DONT HAVE
                            }
                        }, 
                        onComplete: { relayMessage in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
                                    let nrContact = NRContact(contact: contact, following: NosturState.shared.bgFollowingPublicKeys.contains(pubkey))
                                    vm.ready(nrContact)
                                }
                                else { // 4. OR ELSE WE TIMEOUT
                                    vm.timeout()
                                }
                            }
                        }
                    ))
                    vm.fetch()
                }
        case .loading:
            ProgressView()
        case .ready(let nrContact):
            ProfileView(nrContact: nrContact, tab:tab)
        case .timeout:
            VStack {
                Spacer()
                Text("Time-out")
                Button("Try again") { vm.state = .loading; vm.fetch() }
                Spacer()
            }
            .onAppear {
                guard let account = NosturState.shared.account else { return }
                if account.publicKey == pubkey {
                    editingAccount = account
                }
            }
            .sheet(item: $editingAccount) { account in
                NavigationStack {
                    AccountEditView(account: account)
                }
                .presentationBackground(theme.background)
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        ProfileByPubkey(pubkey: "77bbc321087905d98f941bd9d4cc4d2856fdc0f2f083f3ae167544e1a3b39e91")
    }
}
