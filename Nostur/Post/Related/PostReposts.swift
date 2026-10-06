//
//  PostReposts.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/09/2025.


import SwiftUI
import CoreData
import NostrEssentials

struct PostReposts: View {
    
    public let id: String
    
    @Environment(\.theme) var theme
    
    @MainActor
    @State private var viewState: ViewState = .loading
    @State private var isRefreshing = false
    @State private var backlog = Backlog(auto: true, backlogDebugName: "PostReposts")
    @State private var showNotWoT = false
    @State private var showBlocked = false
    
    var body: some View {
        Container {
            switch viewState {
            case .loading:
                CenteredProgressView()
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
                    await refreshCachedReposts()
                }
        })

        .task(id: id) { await refreshReposts() }
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
                if isRefreshing {
                    ProgressView("Loading reposts…")
                } else { Text("No reposts found on the available relays.") }
                Button(action: {
                    Task { await refreshReposts() }
                }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .foregroundColor(theme.accent)
                }
                .disabled(isRefreshing)
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

    @MainActor
    private func refreshCachedReposts() async {
        let contacts = await PostRepostsLoader.load(id: id, blocked: blocks(),
            context: DataProvider.shared().newTaskContext())
        guard !Task.isCancelled else { return }
        viewState = .ready(contacts)
        fetchMissingPs(contacts.inWoT)
    }

    @MainActor
    private func refreshReposts() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        // Show saved rows before waiting for a relay or the shared importer.
        await refreshCachedReposts()
        guard !Task.isCancelled else { isRefreshing = false; return }
        let task = ReqTask(timeout: 5.5,
            reqCommand: { taskId in
                nxReq(Filters(kinds: [6,16], tagFilter: TagFilter(tag: "e", values: [id]), limit: 500), subscriptionId: taskId)
            },
            processResponseCommand: { _, _, _ in
                DataProvider.shared().saveToDiskNow(.bgContext) {
                    Task { @MainActor in
                        await refreshCachedReposts()
                        isRefreshing = false
                    }
                }
            },
            timeoutCommand: { _ in
                Task { @MainActor in isRefreshing = false }
            }, timeoutDelivery: .main)
        backlog.add(task)
        task.fetch()
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


/// A saved repost lookup does not queue behind live feed imports or network work.
enum PostRepostsLoader {
    typealias Contacts = (inWoT: [NRContact], notWoT: [NRContact], blocked: [NRContact])

    static func load(id: String, blocked: Set<String>, context: NSManagedObjectContext) async -> Contacts {
        await context.perform {
            defer { context.reset() }
            let reposts = Event.fetchReposts(id: id, context: context)
            var result: Contacts = ([], [], [])
            var seen = Set<String>()
            for event in reposts where event.deletedById == nil && seen.insert(event.pubkey).inserted {
                let contact: Contact
                if let existing = Contact.fetchByPubkey(event.pubkey, context: context) { contact = existing }
                else { contact = Contact(context: context); contact.pubkey = event.pubkey }
                // Passing the context-owned contact avoids NRContact's shared-context fallback.
                let snapshot = NRContact.instance(of: event.pubkey, contact: contact)
                if blocked.contains(event.pubkey) { result.blocked.append(snapshot) }
                else if event.inWoT { result.inWoT.append(snapshot) }
                else { result.notWoT.append(snapshot) }
            }
            return result
        }
    }
}
