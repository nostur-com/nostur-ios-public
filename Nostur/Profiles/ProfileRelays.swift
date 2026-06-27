//
//  ProfileRelays2.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/12/2023.
//

import SwiftUI
import NostrEssentials
import Combine

struct ProfileRelays: View {
    @Environment(\.theme) private var theme
    public var pubkey: String
    public var name: String
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.created_at, order: .reverse)], predicate: NSPredicate(value: false))
    private var relayListMetadata: FetchedResults<Event>
    
    @State private var relayListItem: Event?
    @State private var dmRelayListItem: Event?
    
    private var writeRelays:[String] {
        guard let relayListItem else { return [] }
        return relayListItem.fastTags.filter { $0.0 == "r" && ($0.2 == nil || $0.2 == "write") }.map { $0.1 }
    }
    
    private var readRelays:[String] {
        guard let relayListItem else { return [] }
        return relayListItem.fastTags.filter { $0.0 == "r" && ($0.2 == nil || $0.2 == "read") }.map { $0.1 }
    }
    
    private var dmRelays:[String] {
        guard let dmRelayListItem else { return [] }
        return dmRelayListItem.fastTags.filter { $0.0 == "relay" }.compactMap { $0.1 }
    }
    
    private var hasRelays: Bool {
        !writeRelays.isEmpty || !readRelays.isEmpty || !dmRelays.isEmpty
    }
    
    @State private var backlog = Backlog(timeout: 3.0, auto: true)
    @State private var loading = true
    @State private var height:CGFloat = 200.0
    
    
    var body: some View {
        NXForm {
            if loading {
                ProgressView()
                    .hCentered()
                    .listRowBackground(theme.background)
                    .task { [weak backlog] in
                        let task = ReqTask(
                            debounceTime: 0.02,
                            subscriptionId: "P-10002-10050",
                            reqCommand: { taskId in
                                guard let rm = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: [Filters(authors: [pubkey], kinds: [10002, 10050])]).json()
                                else {
                                    loading = false
                                    return
                                }
                                req(rm)
                            }, processResponseCommand: { taskId, relayMessage, event in
                                guard let backlog else { return }
                                loading = false
                                backlog.clear()
                            }, timeoutCommand: { taskId in
                                guard let backlog else { return }
                                loading = false
                                backlog.clear()
                            }
                        )
                        backlog?.add(task)
                        task.fetch()
                    }
            }
            else if hasRelays {
                if let relayListItem, !writeRelays.isEmpty {
                    Section {
                        ForEach(writeRelays.indices, id:\.self) { index in
                            HStack {
                                NRTextDynamic(writeRelays[index], plain: true)
                                Spacer()
                                RelayConnectButton(url: writeRelays[index])
                            }
                        }
                    } header: {
                        Text("\(name)'s posts can be found at")
                    } footer: {
                        if readRelays.isEmpty {
                            Text("Last updated \(relayListItem.date.formatted())")
                                .font(.caption)
                                .padding(.top, 40)
                        }
                    }
                    .listRowBackground(theme.background)
                }
                
                if !readRelays.isEmpty {
                    Section {
                        ForEach(readRelays.indices, id:\.self) { index in
                            HStack {
                                NRTextDynamic(readRelays[index], plain: true)
                                Spacer()
                                RelayConnectButton(url: readRelays[index])
                            }
                        }
                    } header: {
                        Text("\(name) reads posts from")
                    }
                    .listRowBackground(theme.background)
                }
                
                if !dmRelays.isEmpty {
                    Section {
                        ForEach(dmRelays.indices, id:\.self) { index in
                            HStack {
                                NRTextDynamic(dmRelays[index], plain: true)
                                Spacer()
                                RelayConnectButton(url: dmRelays[index])
                            }
                        }
                    } header: {
                        Text("\(name)'s private message relays")
                    }
                    .listRowBackground(theme.background)
                }
                
                if let relayListItem {
                    Text("Last updated \(relayListItem.date.formatted())")
                        .font(.caption)
                }

            }
            else {
                Text("\(name) has not published preferred relays or is using an older configuration.")
                    .padding(10)
                    .listRowBackground(theme.background)
            }
        }
        .scrollContentBackgroundHidden()
        .scrollDisabledCompat()
        .frame(height: UIScreen.main.bounds.height * 2.5)
        .background(theme.listBackground)
        .task {
            relayListMetadata.nsPredicate = NSPredicate(format: "kind IN {10002, 10050} AND pubkey == %@", pubkey)
            updateRelayItems()
        }
        .onChange(of: relayListMetadata.map { $0.id }) { _ in
            updateRelayItems()
        }
    }
    
    private func updateRelayItems() {
        relayListItem = relayListMetadata.first(where: { $0.kind == 10002 })
        dmRelayListItem = relayListMetadata.first(where: { $0.kind == 10050 })
    }
}

struct RelayConnectButton: View {
    private var url: String
    @State private var isConnected: Bool = false
    @State private var subscriptions = Set<AnyCancellable>()
    
    init(url: String) {
        self.url = url
    }
    
    var body: some View {
        VStack {
            if isConnected {
                Text("Connected").foregroundColor(.secondary)
            }
            else {
                Button("Connect") {
                    // Connect to relay
                    ConnectionPool.shared.addConnection(RelayData(read: true, write: true, search: false, auth: false, url: normalizeRelayUrl(url), excludedPubkeys: [])) { newConnection in
                     
                        newConnection.connect(forceConnectionAttempt: true)
                        newConnection.objectWillChange.sink { _ in
                            Task { @MainActor in
                                isConnected = newConnection.isConnected
                            }
                        }
                        .store(in: &subscriptions)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            // If connection is successful, save relay to database
                            if newConnection.isConnected {
                                let relay = CloudRelay(context: context())
                                relay.createdAt = Date()
                                relay.url_ = url
                                relay.read = true
                                relay.write = true
                                relay.auth = false
                            }
                        }
                        
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .task {
            if let conn = await ConnectionPool.shared.getConnection(normalizeRelayUrl(url)) {
                isConnected = conn.isConnected
                conn.objectWillChange.sink { _ in
                    Task { @MainActor in
                        isConnected = conn.isConnected
                    }
                }
                .store(in: &subscriptions)
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT","94d6e6f2-2b0c-4f66-a583-aa7d6c06bf8e",{"content":"","created_at":1700698284,"id":"7f48c8958c85985c8b65cd188acabdb35e7ae1bfc2f08bc88b560ec4a0d9f1f3","kind":10002,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","sig":"5fc7ff80e550c3f305f5ee92822eb43d09b450c32a9def89add5b46414ee8b702d76015c15a6b75b1e06aa7b308859396ceaa45a972c8f203b671291ccd26a10","tags":[["r","wss://nostr.wine", "read"],["r","wss://nos.lol", "read"],["r","wss://relay.damus.io","read"]]}]"###,
            ###"["EVENT","94d6e6f2-2b0c-4f66-a583-aa7d6c06bf8e",{"content":"","created_at":1700698285,"id":"c59a2fd3fcb72641ee71f0c8f04074e51fbadf208635a1fd25a2d612c7f6f875","kind":10050,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","sig":"5fc7ff80e550c3f305f5ee92822eb43d09b450c32a9def89add5b46414ee8b702d76015c15a6b75b1e06aa7b308859396ceaa45a972c8f203b671291ccd26a10","tags":[["relay","wss://nos.lol"],["relay","wss://relay.damus.io"]]}]"###
        ])
    }){
        ProfileRelays(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: "Fabian")
    }
}
