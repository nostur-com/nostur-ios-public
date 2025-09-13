//
//  PostReposts.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/09/2025.


import SwiftUI
import NostrEssentials

struct PostReposts: View {
    
    public let id: String
    
    @Environment(\.theme) var theme
    
    @MainActor
    @State private var viewState: ViewState = .loading
    
    var body: some View {
        Container {
            switch viewState {
            case .loading:
                CenteredProgressView()
                    .task(id: "reposts") {
                        viewState = await loadReposts(id: id)
                    }
            case .ready(let nrContacts):
                NXList(plain: true, showListRowSeparator: true) {
                    if nrContacts.isEmpty {
                        ZStack(alignment: .center) {
                            theme.listBackground
                            VStack(spacing: 20) {
                                Text("Nothing here :(")
                                Button(action: {
                                    
                                }) {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .labelStyle(.iconOnly)
                                        .foregroundColor(theme.accent)
                                }
                            }
                        }
                    }
                    else {
                        ForEach(nrContacts) { nrContact in
                            NRProfileRow(nrContact: nrContact)
                        }
                    }
                }
            case .error(let message):
                Text(message ?? "Error")
            }
        }

        .onReceive(  ViewUpdates.shared.relatedUpdates
            .filter { $0.type == .Reposts && $0.eventId == self.id }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main), perform: { _ in
                Task {
                    viewState = await loadReposts(id: id)
                }
        })
        
        .navigationTitle("Reposted by")
    }
    
    private func loadReposts(id: String) async -> ViewState {
        _ = try? await relayReq(Filters(kinds: [6], tagFilter: TagFilter(tag: "e", values: [id])), timeout: 5.5)
        
        // Get reposts, return related contact
        let nrContacts: [NRContact] = await withBgContext { bg in
            Event.fetchReposts(id: id)
                .map { NRContact.instance(of: $0.pubkey )}
        }
        
        Task { fetchMissingPs(nrContacts) }
        
        return ViewState.ready(nrContacts)
    }
}

extension PostReposts {
    enum ViewState {
        case loading
        case ready([NRContact])
        case error(String?)
    }
}

#Preview {
    PostReposts(id: "e94ac42f1f09ae06fa7b7eaaee199e29d6c45537308a198f89cad91624f999a2")
}

