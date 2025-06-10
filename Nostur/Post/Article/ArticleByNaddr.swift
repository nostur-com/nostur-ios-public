//
//  ArticleByNaddr.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2023.
//

import SwiftUI

struct ArticleByNaddr: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var dim: DIMENSIONS
    public let naddr1: String
    public var navigationTitle: String? = nil
    public var navTitleHidden: Bool = false
    public var theme: Theme = Themes.default.theme
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
    
    var body: some View {
        VStack {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                HStack(spacing: 5) {
                    ProgressView()
                    if vm.state == .initializing || vm.state == .loading {
                        Text("Fetching...")
                    }
                    else if vm.state == .altLoading {
                        Text("Trying more relays...")
                    }
                }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear { [weak vm] in
                        guard let naddr = try? ShareableIdentifier(naddr1),
                              let kind = naddr.kind,
                              let pubkey = naddr.pubkey,
                              let definition = naddr.eventId
                        else {
                            return
                        }
                        
                        
                        let fetchParams: FetchVM.FetchParams = (
                            prio: true,
                            req: { [weak vm] taskId in
                                bg().perform { [weak vm] in // 1. CHECK LOCAL DB
                                    guard let vm else { return }
                                    if let event = Event.fetchReplacableEvent(kind,
                                                                                   pubkey: pubkey,
                                                                                   definition: definition,
                                                                                   context: bg()) {
                                        vm.ready(NRPost(event: event, withFooter: false))
                                    }
                                    else { // 2. ELSE CHECK RELAY
                                        req(RM.getArticle(pubkey: pubkey, kind:Int(kind), definition: definition, subscriptionId: taskId))
                              
                                    }
                                }
                            },
                            onComplete: { [weak vm] relayMessage, event in
                                guard let vm else { return }
                                if let event = event {
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                else if let event = Event.fetchReplacableEvent(kind,
                                                                                    pubkey: pubkey,
                                                                                    definition: definition,
                                                                                    context: bg()) { // 3. WE FOUND IT ON RELAY
                                    if vm.state == .altLoading, let relay = naddr.relays.first {
                                        L.og.debug("Event found on using relay hint: \(event.id) - \(relay)")
                                    }
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                // Still don't have the event? try to fetch from relay hint
                                // TODO: Should try a relay we don't already have in our relay set
                                else if (settings.followRelayHints && vpnGuardOK()) && [.initializing, .loading].contains(vm.state) {
                                    // try search relays and relay hint
                                    vm.altFetch()
                                }
                                else { // 5. TIMEOUT
                                    vm.timeout()
                                }
                            },
                            altReq: { taskId in // IF WE HAVE A RELAY HINT WE USE THIS REQ, TRIGGERED BY vm.altFetch()
                                // Try search relays
                                req(RM.getArticle(pubkey: pubkey, kind:Int(kind), definition: definition, subscriptionId: taskId), relayType: .SEARCH)
                                guard let relay = naddr.relays.first else { return }
                                
                                L.og.debug("FetchVM.3 HINT \(relay)")
                                ConnectionPool.shared.sendEphemeralMessage(
                                    RM.getArticle(pubkey: pubkey, kind:Int(kind), definition: definition, subscriptionId: taskId),
                                    relay: relay
                                )
                            }
                            
                        )
                        vm?.setFetchParams(fetchParams)
                        vm?.fetch()
                    }
            case .ready(let nrPost):
                if nrPost.kind == 30023 {
                    ArticleView(nrPost, isDetail: true, navTitleHidden: navTitleHidden, theme: theme)
                }
                else {
                    PostDetailView(nrPost: nrPost, navTitleHidden: navTitleHidden)
                }
            case .timeout:
                Text("Unable to fetch content")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
