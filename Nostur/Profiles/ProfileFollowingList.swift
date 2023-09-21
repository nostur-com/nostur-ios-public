//
//  ProfileFollowingList.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct FollowsInfo: Identifiable, Equatable {
    let id = UUID()
    let follows:[String]
    let silentFollows:[String]
}

struct ProfileFollowingList: View {
    let pubkey:String
    
    @StateObject private var vm = FetchVM<FollowsInfo>() // Array of following pubkeys and array of silent follow pubkeys

    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            ProgressView()
                .padding(10)
                .frame(maxWidth:.infinity, alignment: .center)
                .onAppear {
                    vm.setFetchParams((
                        req: {
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    
                                    let silentFollows = clEvent.pubkey == account()?.publicKey
                                        ? ((account()?.follows_.filter { $0.privateFollow }.map { $0.pubkey }) ?? [])
                                        : []
                                    
                                    let pubkeys = clEvent.fastPs.map({ $0.1 })
                                    
                                    vm.ready(FollowsInfo(follows: pubkeys, silentFollows: silentFollows))
                                }
                                else { req(RM.getAuthorContactsList(pubkey: pubkey)) }
                            }
                        }, 
                        onComplete: { relayMessage in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    let silentFollows = clEvent.pubkey == account()?.publicKey
                                        ? ((account()?.follows_.filter { $0.privateFollow }.map { $0.pubkey }) ?? [])
                                        : []
                                    
                                    let pubkeys = clEvent.fastPs.map({ $0.1 })
                                    
                                    vm.ready(FollowsInfo(follows: pubkeys, silentFollows: silentFollows))
                                }
                                else { vm.timeout() }
                            }
                        },
                        altReq: nil
                    ))
                    vm.fetch()
                }
        case .ready(let followsInfo):
            ContactList(pubkeys: followsInfo.follows, silent: followsInfo.silentFollows)
        case .timeout:
            VStack(alignment: .center) {
                Text("Unable to fetch contacts")
                Button("Try again") { vm.fetch() }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
        case .error(let error):
            Text(error)
        }
    }
}
