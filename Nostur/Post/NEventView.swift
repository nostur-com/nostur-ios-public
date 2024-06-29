//
//  NEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/05/2023.
//

import SwiftUI

struct NEventView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var dim: DIMENSIONS
    public let identifier: ShareableIdentifier
    public var forceAutoload: Bool = false
    public var theme: Theme
    @StateObject private var vm = FetchVM<NRPost>(timeout: 5.0, debounceTime: 0.05)
        
    var body: some View {
        Group {
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
                    .onAppear { [weak vm, weak dim] in
                        guard let eventId = identifier.eventId else {
                            vm?.error("Problem parsing nostr identifier")
                            return
                        }
                        let fetchParams: FetchVM.FetchParams = (
                            prio: true,
                            req: { [weak vm, weak dim] taskId in
                                bg().perform { [weak vm, weak dim] in // 1. CHECK LOCAL DB
                                    guard let vm, let dim else { return }
                                    if let event = try? Event.fetchEvent(id: eventId, context: bg()) {
                                        vm.ready(NRPost(event: event, withFooter: false, isScreenshot: dim.isScreenshot))
                                    }
                                    else { // 2. ELSE CHECK RELAY
                                        req(RM.getEvent(id: eventId, subscriptionId: taskId))
                                    }
                                }
                            },
                            onComplete: { [weak vm, weak dim] relayMessage, event in
                                guard let vm, let dim else { return }
                                if let event = event {
                                    vm.ready(NRPost(event: event, withFooter: false, isScreenshot: dim.isScreenshot))
                                }
                                else if let event = try? Event.fetchEvent(id: eventId, context: bg()) { // 3. WE FOUND IT ON RELAY
                                    if vm.state == .altLoading, let relay = identifier.relays.first {
                                        L.og.debug("Event found on using relay hint: \(eventId) - \(relay)")
                                    }
                                    vm.ready(NRPost(event: event, withFooter: false, isScreenshot: dim.isScreenshot))
                                }
                                // Still don't have the event? try to fetch from relay hint
                                // TODO: Should try a relay we don't already have in our relay set
                                else if settings.followRelayHints && [.initializing, .loading].contains(vm.state) {
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
                                
                                L.og.debug("FetchVM.3 HINT \(eventId)")
                                ConnectionPool.shared.sendEphemeralMessage(
                                    RM.getEvent(id: eventId, subscriptionId: taskId),
                                    relay: relay
                                )
                            }
                            
                        )
                        vm?.setFetchParams(fetchParams)
                        vm?.fetch()
                    }
            case .ready(let nrPost):
                EmbeddedPost(nrPost, forceAutoload: forceAutoload, theme: theme)
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
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
        )
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
                    NEventView(identifier: identifier, theme: Themes.default.theme)
                }
            }
        }
    }
}
