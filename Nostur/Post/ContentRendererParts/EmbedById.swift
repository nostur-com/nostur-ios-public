//
//  EmbedById.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/09/2023.
//

import SwiftUI
import NostrEssentials

struct EmbedById: View {
    @Environment(\.theme) private var theme
    public let id: String
    public var fullWidth: Bool = false
    public var forceAutoload: Bool = false
    @StateObject private var vm = FetchVM<NRPost>(timeout: 1.5, debounceTime: 0.05)
    @State private var nevent: String? = nil
    
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
            KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: true, isDetail: false, isEmbedded: true)
            
        case .timeout:
            VStack {
                Text("Unable to fetch content:")
                    .onAppear {
                        nevent = (try? NostrEssentials.ShareableIdentifier("nevent", id: id))?.identifier
                    }
                if let nevent {
                    CopyableTextView(text: nevent, copyText: nevent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Retry") { [weak vm] in
                    vm?.state = .initializing
                    vm?.fetch()
                }
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
    
    private func load() {
        let eventId = self.id
        let fetchParams: FetchVM.FetchParams = (
            prio: true,
            req: { [weak vm = self.vm] taskId in
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
            onComplete: { [weak vm = self.vm] relayMessage, event in
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
        self.vm.setFetchParams(fetchParams)
        self.vm.fetch()
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadPosts() }) {
        if let post = PreviewFetcher.fetchNRPost() {
            EmbedById(id: post.id)
        }
    }
}
