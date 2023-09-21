//
//  ProfileFollowingCount.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct ProfileFollowingCount: View {
    let pubkey:String
    
    @StateObject private var vm = FetchVM<Int>()

    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            Text("\(Image(systemName: "hourglass.circle.fill")) Following", comment: "Label for Following count")
                .onAppear {
                    vm.setFetchParams((
                        req: {
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    vm.ready(clEvent.pTags().count)
                                }
                                else { req(RM.getAuthorContactsList(pubkey: pubkey)) }
                            }
                        }, 
                        onComplete: { relayMessage in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                    vm.ready(clEvent.pTags().count)
                                }
                                else { vm.timeout() }
                            }
                        },
                        altReq: nil
                    ))
                    vm.fetch()
                }
        case .ready(let count):
            Text("\(count) Following", comment: "Label for Following count")
        case .timeout:
            Text("\(Image(systemName: "person.fill.questionmark")) Following", comment: "Label for Following count")
                .onTapGesture {
                    vm.state = .loading
                    vm.fetch()
                }
        case .error(let error):
            Text(error)
        }
    }
}
