//
//  ProfileFollowingCount.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct ProfileFollowingCount: View {
    let pubkey: String
    
    @StateObject private var vm = FetchVM<Int>()

    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            Text("\(Image(systemName: "hourglass.circle.fill")) Following", comment: "Label for Following count")
                .onAppear { [weak vm] in
                    let fetchParams: FetchVM.FetchParams = (
                        prio: false,
                        req: { [weak vm] _ in // TODO: can we use prio here? not sure if properly replaced, should check
                            bg().perform { [weak vm] in // 1. FIRST CHECK LOCAL DB
                                guard let vm else { return }
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    vm.ready(clEvent.pTags().count)
                                }
                                else { req(RM.getAuthorContactsList(pubkey: pubkey)) }
                            }
                        },
                        onComplete: { [weak vm] relayMessage, _ in
                            bg().perform { [weak vm] in // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                guard let vm else { return }
                                if case .ready(_) = vm.state { return }
                                
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    vm.ready(clEvent.pTags().count)
                                }
                                else { vm.timeout() }
                            }
                        },
                        altReq: nil
                    )
                    vm?.setFetchParams(fetchParams)
                    guard let vm else { return }
                    vm.fetch()
                }
        case .ready(let count):
            Text("\(count) Following", comment: "Label for Following count")
        case .timeout:
            Text("\(Image(systemName: "person.fill.questionmark")) Following", comment: "Label for Following count")
                .onTapGesture { [weak vm] in
                    vm?.state = .loading
                    vm?.fetch()
                }
        case .error(let error):
            Text(error)
        }
    }
}
