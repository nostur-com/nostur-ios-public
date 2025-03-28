//
//  EmbedById.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/09/2023.
//

import SwiftUI

struct EmbedById: View {
    @EnvironmentObject private var dim: DIMENSIONS
    public let id: String
    public var fullWidth: Bool = false
    public var forceAutoload: Bool = false
    public var theme: Theme
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
    
    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            CenteredProgressView()
                .frame(height: 250)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .onBecomingVisible {
                    self.load()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
        case .ready(let nrPost):
            KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: true, isDetail: false, isEmbedded: true, theme: theme)
            
        case .timeout:
            VStack {
                Text("Unable to fetch content")
                Button("Retry") { [weak vm] in
                    vm?.state = .loading
                    vm?.fetch()
                }
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
    
    private func load() {
        let id = id
        let fetchParams: FetchVM.FetchParams = (
            prio: true,
            req: { [weak vm = self.vm, weak dim = self.dim] taskId in
                bg().perform {
                    guard let vm, let dim else { return }
                    if let event = Event.fetchEvent(id: id, context: bg()) {
                        vm.ready(NRPost(event: event, withFooter: false, isScreenshot: dim.isScreenshot))
                    }
                    else {
                        req(RM.getEvent(id: id, subscriptionId: taskId))
                    }
                }
            },
            onComplete: { [weak vm = self.vm, weak dim = self.dim] relayMessage, event in
                guard let vm, let dim else { return }
                if let event = event {
                    vm.ready(NRPost(event: event, withFooter: false, isScreenshot: dim.isScreenshot))
                }
                else if let event = Event.fetchEvent(id: id, context: bg()) {
                    vm.ready(NRPost(event: event, withFooter: false, isScreenshot: dim.isScreenshot))
                }
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
                req(RM.getEvent(id: self.id, subscriptionId: taskId), relayType: .SEARCH)
            }
        )
        self.vm.setFetchParams(fetchParams)
        self.vm.fetch()
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadPosts() }) {
        if let post = PreviewFetcher.fetchNRPost() {
            EmbedById(id: post.id, theme: Themes.default.theme)
        }
    }
}
