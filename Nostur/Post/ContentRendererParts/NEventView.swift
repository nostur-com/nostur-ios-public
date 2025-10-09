//
//  NEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/05/2023.
//

import SwiftUI

struct NEventView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    public let identifier: ShareableIdentifier
    public var fullWidth: Bool = false
    public var forceAutoload: Bool = false
    
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
        
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
            .onBecomingVisible { [weak vm] in
                guard let eventId = identifier.eventId else {
                    vm?.error("Problem parsing nostr identifier")
                    return
                }
                let fetchParams: FetchVM.FetchParams = (
                    prio: true,
                    req: { [weak vm] taskId in
                        bg().perform { [weak vm] in // 1. CHECK LOCAL DB
                            guard let vm else { return }
                            if let event = Event.fetchEvent(id: eventId, context: bg()) {
                                vm.ready(NRPost(event: event, withFooter: false))
                            }
                            else { // 2. ELSE CHECK RELAY
                                req(RM.getEvent(id: eventId, subscriptionId: taskId))
                            }
                        }
                    },
                    onComplete: { [weak vm] relayMessage, event in
                        guard let vm else { return }
                        if let event = event {
                            vm.ready(NRPost(event: event, withFooter: false))
                        }
                        else if let event = Event.fetchEvent(id: eventId, context: bg()) { // 3. WE FOUND IT ON RELAY
                            if vm.state == .altLoading, let relay = identifier.relays.first {
#if DEBUG
                                L.og.debug("Event found on using relay hint: \(eventId) - \(relay)")
#endif
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
                        req(RM.getEvent(id: eventId, subscriptionId: taskId), relayType: .SEARCH)
                        guard let relay = identifier.relays.first else { return }
                        
#if DEBUG
                        L.og.debug("FetchVM.3 HINT \(eventId)")
#endif
                        ConnectionPool.shared.sendEphemeralMessage(
                            RM.getEvent(id: eventId, subscriptionId: taskId),
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
            Text("Unable to fetch content")
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

struct NEventView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NBNavigationStack {
                if let identifier = try? ShareableIdentifier("nevent1qqspg0h7quunckc8a7lxag0uvmpeewv9hx8cs3r9pmwsp77tqsfz3gcens7um") {
                    NEventView(identifier: identifier)
                }
            }
        }
    }
}
