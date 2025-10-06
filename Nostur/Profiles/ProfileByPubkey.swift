//
//  ProfileByPubkey.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct ProfileByPubkey: View {
    @Environment(\.theme) private var theme
    
    public let pubkey: String
    public var tab: String?
        
    @State private var editingAccount: CloudAccount? = nil
    @StateObject private var vm = FetchVM<NRContact>(timeout: 1.5, debounceTime: 0.05)

    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            ProgressView()
                .frame(alignment: .center)
                .onAppear { [weak vm] in
                    // Always fetch latest kind 0
                    nxReq(Filters(authors: [pubkey], kinds: [0]), subscriptionId: UUID().uuidString)
                    if let cachedNRContact = NRContactCache.shared.retrieveObject(at: pubkey) {
                        vm?.ready(cachedNRContact)
                        return
                    }
                    
                    vm?.setFetchParams((
                        prio: false,
                        req: { taskId in
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                guard let vm else { return }
                                if let nrContact = NRContact.fetch(pubkey) {
                                    vm.ready(nrContact) // 2A. DONE
                                }
                                else { // Check .SEARCH relays
                                    nxReq(Filters(authors: [pubkey], kinds: [0]), subscriptionId: taskId, relayType: .SEARCH)
                                }
                            }
                        }, 
                        onComplete: { relayMessage, _ in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                guard let vm else { return }
                                if let nrContact = NRContact.fetch(pubkey) {
                                    vm.ready(nrContact)
                                }
                                else { // 4. OR ELSE WE TIMEOUT
                                    vm.timeout()
                                }
                            }
                        },
                        altReq: nil
                    ))
                    guard let vm else { return }
                    vm.fetch()
                }
        case .ready(let nrContact):
            ProfileView(nrContact: nrContact, tab:tab)
                .preference(key: TabTitlePreferenceKey.self, value: nrContact.anyName)
        case .timeout:
            VStack {
                Spacer()
                Text("Time-out")
                Button("Try again") { vm.state = .loading; vm.fetch() }
                Spacer()
            }
            .onAppear {
                guard let account = account() else { return }
                if account.publicKey == pubkey {
                    editingAccount = account
                }
            }
            .sheet(item: $editingAccount) { account in
                NBNavigationStack {
                    AccountEditView(account: account)
                        .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(theme.listBackground)
            }
        case .error(let error):
            Text(error)
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
