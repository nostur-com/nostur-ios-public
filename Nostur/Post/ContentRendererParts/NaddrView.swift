//
//  NaddrView.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/09/2024.
//

import SwiftUI

struct NaddrView: View {
    @Environment(\.theme) private var theme: Theme
    @EnvironmentObject private var settings: SettingsStore
    
    public let naddr1: String
    public var navigationTitle: String? = nil
    public var navTitleHidden: Bool = false
    public var fullWidth: Bool = false
    public var forceAutoload: Bool = false
    
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05, backlogDebugName: "NaddrView")
    
    var body: some View {
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
            .task { [weak vm] in
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
                                vm.ready(NRPost(event: event))
                            }
                            else { // 2. ELSE CHECK RELAY
                                req(RM.getArticle(pubkey: pubkey, kind:Int(kind), definition: definition, subscriptionId: taskId))
                        
                            }
                        }
                    },
                    onComplete: { [weak vm] relayMessage, event in
                        guard let vm else { return }
                        if case .ready(_) = vm.state { return }
                        
                        if let event = event, event.aTag == naddr.aTag {
                            vm.ready(NRPost(event: event))
                        }
                        else if let event = Event.fetchReplacableEvent(kind,
                                                                            pubkey: pubkey,
                                                                            definition: definition,
                                                                            context: bg()) { // 3. WE FOUND IT ON RELAY
#if DEBUG
                            if vm.state == .altLoading, let relay = naddr.relays.first {
                                L.og.debug("Event found on using relay hint: \(event.id) - \(relay)")
                            }
#endif
                            vm.ready(NRPost(event: event))
                        }
                        // Still don't have the event? try to fetch from relay hint
                        // TODO: Should try a relay we don't already have in our relay set
                        // This is skipped if we are .altLoading, goes to .timeout()
                        else if (settings.followRelayHints && vpnGuardOK()) && [.initializing, .loading].contains(vm.state) {
                            // try search relays and relay hint
                            vm.altFetch()
                        }
                        else { // 5. TIMEOUT
                            vm.timeout()
                        }
                    },
                    altReq: { taskId in
                        // Try search relays
                        req(RM.getArticle(pubkey: pubkey, kind:Int(kind), definition: definition, subscriptionId: taskId), relayType: .SEARCH)
                        
                        // IF WE HAVE A RELAY HINT WE USE THIS REQ, TRIGGERED BY vm.altFetch()
                        guard let relay = naddr.relays.first else { return }
                        
#if DEBUG
                        L.og.debug("FetchVM.3 HINT \(relay)")
#endif
                        ConnectionPool.shared.sendEphemeralMessage(
                            RM.getArticle(pubkey: pubkey, kind:Int(kind), definition: definition, subscriptionId: taskId),
                            relay: relay
                        )
                    }
                    
                )
                vm?.setFetchParams(fetchParams)
                vm?.fetch()
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.lineColor, lineWidth: 1)
            )
        case .ready(let nrPost):
            KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: true, isDetail: false, isEmbedded: true)
            
        case .timeout:
            VStack {
                Text("Unable to fetch content:")
                CopyableTextView(text: naddr1, copyText: naddr1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Retry")
                    .highPriorityGesture(TapGesture().onEnded({ [weak vm] _ in
                        vm?.state = .initializing
                    }))
                .foregroundStyle(theme.accent)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.lineColor, lineWidth: 1)
            )
            
        case .error(let error):
            Text(error)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
        }
    }
}

import NavigationBackport

struct NaddrView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.parseMessages([
                ###"["EVENT","naddr",{"pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","content":"","created_at":1727636264,"tags":[["d","4d445de7-cfc0-426b-af44-f7167c3358dd"],["title","New stream key, who dis"],["summary",""],["image","https://dvr.zap.stream/zap-stream-dvr/4d445de7-cfc0-426b-af44-f7167c3358dd/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J&Expires=33284545008&Signature=MiLQ7D%2FpVT6tINZ8fzEa1uCpPVY%3D"],["status","live"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","wss://relay.zap.stream","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1727091981"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/4d445de7-cfc0-426b-af44-f7167c3358dd.m3u8"],["current_participants","2"]],"sig":"69bf01154dc1d553b28620d1b1380fd7649258d879e1fb8d736e037047743f9380619708b45f2215386bae45bcfe22324ca0bb898a5e96d03833ea1a92f69d6d","id":"58865e55c7cbfb7c729f1513aeddc950a44880ae86f0f4e5cae6e693a805aef0","kind":30311}]"###
            ])
        }) {
            NBNavigationStack {
                if let identifier = try? ShareableIdentifier("naddr1qqjrgep5xs6kgefh943kvces956rydnz94skvdp594nrwvfkxa3nxve48pjxgq3qeaz6dwsnvwkha5sn5puwwyxjgy26uusundrm684lg3vw4ma5c2jsxpqqqpmxwqgcwaehxw309aex2mrp0yh8xmn0wf6zuum0vd5kzmqpp4mhxue69uhkummn9ekx7mqpz3mhxue69uhhyetvv9ujuerpd46hxtnfduq3vamnwvaz7tmjv4kxz7fwdehhxarj9e3xzmnyt86q2r") {
                    NaddrView(naddr1: identifier.bech32string)
                }
            }
        }
    }
}
