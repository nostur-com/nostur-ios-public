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
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .center)
                .onAppear { [weak vm] in
                    let fetchParams: FetchVM.FetchParams = (
                        prio: false, // Can't use prio, different relays can send different event and we need most recent.
                        req: { _ in
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                guard let vm else { return }
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    
                                    let silentFollows:Set<String> = clEvent.pubkey == account()?.publicKey
                                        ? (account()?.privateFollowingPubkeys ?? [])
                                        : []
                                    
                                    let pubkeys = clEvent.fastPs.map({ $0.1 })
                                    
                                    vm.ready(FollowsInfo(follows: pubkeys, silentFollows:
                                                            Array(silentFollows)))
                                }
                                else { req(RM.getAuthorContactsList(pubkey: pubkey)) }
                            }
                        },
                        onComplete: { [weak vm] relayMessage, _ in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                guard let vm else { return }
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    let silentFollows:Set<String> = clEvent.pubkey == account()?.publicKey
                                        ? (account()?.privateFollowingPubkeys ?? [])
                                        : []
                                    
                                    let pubkeys = clEvent.fastPs.map({ $0.1 })
                                    
                                    vm.ready(FollowsInfo(follows: pubkeys, silentFollows: Array(silentFollows)))
                                }
                                else { vm.timeout() }
                            }
                        },
                        altReq: nil
                    )
                    vm?.setFetchParams(fetchParams)
                    vm?.fetch()
                }
        case .ready(let followsInfo):
            ContactList(pubkeys: followsInfo.follows, silent: followsInfo.silentFollows)
        case .timeout:
            VStack(alignment: .center) {
                Text("Unable to fetch contacts")
                Button("Try again") { [weak vm] in
                    vm?.fetch()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
        case .error(let error):
            Text(error)
        }
    }
}
