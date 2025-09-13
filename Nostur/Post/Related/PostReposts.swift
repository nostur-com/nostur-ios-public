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
    @State private var showNotWoT = false
    @State private var showBlocked = false
    
    var body: some View {
        Container {
            switch viewState {
            case .loading:
                CenteredProgressView()
                    .task(id: "reposts") {
                        viewState = await loadReposts(id: id)
                    }
            case .ready(let contactsTuple):
                NXList(plain: true, showListRowSeparator: true) {
                    if contactsTuple.inWoT.isEmpty && contactsTuple.notWoT.isEmpty && contactsTuple.blocked.isEmpty {
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
                        ForEach(contactsTuple.inWoT) { nrContact in
                            NRProfileRow(nrContact: nrContact)
                        }
                        
                        if WOT_FILTER_ENABLED() && !contactsTuple.notWoT.isEmpty && !showNotWoT {
                            Button {
                                showNotWoT = true
                                Task { fetchMissingPs(contactsTuple.notWoT) }
                            } label: {
                                Text("Show more (\(contactsTuple.notWoT.count))")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .padding(.bottom, 10)
                        }
                        if showNotWoT {
                            ForEach(contactsTuple.notWoT) { nrContact in
                                NRProfileRow(nrContact: nrContact)
                            }
                        }
                        
                        if !contactsTuple.blocked.isEmpty && !showBlocked {
                            Button {
                                showBlocked = true
                                Task { fetchMissingPs(contactsTuple.blocked) }
                            } label: {
                                Text("Show blocked (\(contactsTuple.blocked.count))")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .padding(.bottom, 10)
                        }
                        
                        if showBlocked {
                            ForEach(contactsTuple.blocked) { nrContact in
                                NRProfileRow(nrContact: nrContact)
                            }
                        }
                    }
                }
            case .error(let message):
                Text(message ?? "Error")
                    .centered()
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
        let nrContacts: ([NRContact], [NRContact], [NRContact]) = await withBgContext { bg in
            let blocked = blocks()
            let reposts = Event.fetchReposts(id: id)
            return (
                reposts.filter { $0.inWoT && !blocked.contains($0.pubkey) }
                    .map { NRContact.instance(of: $0.pubkey ) },
                reposts.filter { !$0.inWoT && !blocked.contains($0.pubkey) }
                    .map { NRContact.instance(of: $0.pubkey ) },
                reposts.filter { blocked.contains($0.pubkey) }
                    .map { NRContact.instance(of: $0.pubkey ) }
            )
        }
        
        Task { fetchMissingPs(nrContacts.0) }
        
        return ViewState.ready(nrContacts)
    }
}

extension PostReposts {
    enum ViewState {
        case loading
        case ready((inWoT: [NRContact], notWoT: [NRContact], blocked: [NRContact])) // inWoT, notInWoT, blocked
        case error(String?)
    }
}

#Preview {
    PostReposts(id: "e94ac42f1f09ae06fa7b7eaaee199e29d6c45537308a198f89cad91624f999a2")
}

