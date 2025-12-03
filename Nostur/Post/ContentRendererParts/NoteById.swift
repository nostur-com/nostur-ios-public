//
//  NoteById.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI

struct NoteById: View {
    @Environment(\.theme) private var theme
    public let id: String
    public var navTitleHidden: Bool = false
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
    
    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .onBecomingVisible { [weak vm] in
                    let eventId = self.id
                    let fetchParams: FetchVM.FetchParams = (
                        prio: true,
                        req: { [weak vm] taskId in
                            bg().perform {
                                guard let vm else { return }
                                if let event = Event.fetchEvent(id: eventId, context: bg()) {
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                else {
                                    req(RM.getEvent(id: eventId, subscriptionId: taskId))
                                }
                            }
                        },
                        onComplete: { [weak vm] relayMessage, event in
                            guard let vm else { return }
                            if case .ready(_) = vm.state { return }
                            
                            if let event = event, event.id == eventId {
                                vm.ready(NRPost(event: event, withFooter: false))
                            }
                            else if let event = Event.fetchEvent(id: eventId, context: bg()) {
                                vm.ready(NRPost(event: event, withFooter: false))
                            }
                            // This is skipped if we are .altLoading, goes to .timeout()
                            else if [.initializing, .loading].contains(vm.state) {
                                // try search relays
                                vm.altFetch()
                            }
                            else {
                                vm.timeout()
                            }
                        },
                        altReq: { taskId in
                            // Try search relays
                            req(RM.getEvent(id: eventId, subscriptionId: taskId), relayType: .SEARCH)
                        }
                    )
                    vm?.setFetchParams(fetchParams)
                    vm?.fetch()
                }
        case .ready(let nrPost):
            if nrPost.kind == 30023 {
                ArticleView(nrPost, isDetail: true, fullWidth: SettingsStore.shared.fullWidthImages, hideFooter: false)
            }
            else {
                PostDetailView(nrPost: nrPost, navTitleHidden: navTitleHidden)
//                    .debugDimensions("NoteById.PostDetailView", alignment: .topLeading)
            }
        case .timeout:
            Text("Unable to fetch")
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
        case .error(let error):
            Text(error)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
