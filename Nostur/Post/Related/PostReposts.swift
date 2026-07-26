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
                reposts(contactsTuple)
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

    @ViewBuilder
    private func reposts(_ contactsTuple: (inWoT: [NRContact], notWoT: [NRContact], blocked: [NRContact])) -> some View {
        if contactsTuple.inWoT.isEmpty && contactsTuple.notWoT.isEmpty && contactsTuple.blocked.isEmpty {
            emptyState
        }
        else {
            ScrollView {
                VStack(spacing: GUTTER) {
                    LazyVStack(spacing: GUTTER) {
                        ForEach(contactsTuple.inWoT) { nrContact in
                            NRProfileRow(nrContact: nrContact)
                        }
                    }

                    if WOT_FILTER_ENABLED() && !contactsTuple.notWoT.isEmpty && !showNotWoT {
                        showMoreButton(contactsTuple.notWoT)
                    }

                    if showNotWoT || !WOT_FILTER_ENABLED() {
                        LazyVStack(spacing: GUTTER) {
                            ForEach(contactsTuple.notWoT) { nrContact in
                                NRProfileRow(nrContact: nrContact)
                            }
                        }
                    }

                    if !contactsTuple.blocked.isEmpty && !showBlocked {
                        showBlockedButton(contactsTuple.blocked)
                    }

                    if showBlocked {
                        LazyVStack(spacing: GUTTER) {
                            ForEach(contactsTuple.blocked) { nrContact in
                                NRProfileRow(nrContact: nrContact)
                            }
                        }
                    }
                }
                .foregroundColor(theme.accent)
            }
            .background(theme.listBackground)
        }
    }

    private var emptyState: some View {
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

    private func showMoreButton(_ contacts: [NRContact]) -> some View {
        Button {
            showNotWoT = true
            Task { fetchMissingPs(contacts) }
        } label: {
            Text("Show more (\(contacts.count))")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    private func showBlockedButton(_ contacts: [NRContact]) -> some View {
        Button {
            showBlocked = true
            Task { fetchMissingPs(contacts) }
        } label: {
            Text("Show blocked (\(contacts.count))")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
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
