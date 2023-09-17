//
//  ProfileFollowingList.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct ProfileFollowingList: View {
    let pubkey:String
    
    @StateObject private var vm = FetchVM<([String],[String])>() // Array of following pubkeys and array of silent follow pubkeys

    var body: some View {
        switch vm.state {
        case .initializing:
            CenteredProgressView()
                .onAppear {
                    vm.setFetchParams((
                        req: {
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    
                                    let silentFollows = clEvent.pubkey == NosturState.shared.bgActiveAccountPublicKey
                                        ? ((NosturState.shared.bgAccount?.follows_.filter { $0.privateFollow }.map { $0.pubkey }) ?? [])
                                        : []
                                    
                                    let pubkeys = clEvent.fastPs.map({ $0.1 })
                                    
                                    vm.ready((pubkeys, silentFollows))
                                }
                                else { req(RM.getAuthorContactsList(pubkey: pubkey)) }
                            }
                        }, 
                        onComplete: { relayMessage in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    let silentFollows = clEvent.pubkey == NosturState.shared.bgActiveAccountPublicKey
                                        ? ((NosturState.shared.bgAccount?.follows_.filter { $0.privateFollow }.map { $0.pubkey }) ?? [])
                                        : []
                                    
                                    let pubkeys = clEvent.fastPs.map({ $0.1 })
                                    
                                    vm.ready((pubkeys, silentFollows))
                                }
                                else { vm.timeout() }
                            }
                        }
                    ))
                    vm.fetch()
                }
        case .loading:
            CenteredProgressView()
        case .ready(let (pubkeys, silentFollows)):
            ContactList(pubkeys: pubkeys, silent:silentFollows)
        case .timeout:
            VStack(alignment: .center) {
                Spacer()
                Text("Time-out")
                Button("Try again") { vm.fetch() }
                Spacer()
            }
        }
    }
}
