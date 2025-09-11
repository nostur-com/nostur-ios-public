//
//  RepublishRestrictedPostSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

// republish own restricted post - needs auth
// similar to RepublishPostSheet, but starts with auth right away as restricted posts need that
struct RepublishRestrictedPostSheet: View {
    @Environment(\.theme) private var theme
    
    @ObservedObject public var nrPost: NRPost // Should be restricted ["-"] post, use check in container, not this view
    public var rootDismiss: (() -> Void)? = nil
    
    @State private var relays: [RelayData] = []
    
    enum ViewState {
        case loading // needed or .task { } will rerun when navigating back
        case selecting
        case publishing
    }
    
    @State private var viewState: ViewState = .loading
    @State private var relayStates: [RelayData: RelayState] = [:]
    @State private var signingAccount: CloudAccount?
    @State private var signingAccountPubkey: String?
    @State private var logs = ""

    var body: some View {
        NXForm {
            Section(header: Text("Republish to", comment: "Header for a feed setting")) {
                ForEach(relays, id:\.id) { relay in
                    HStack {
                        RelayStateCheckbox(relayState: relayStates[relay] ?? .unselected)
                        Text(relay.url)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let relayState = relayStates[relay], relayState == .authRequired {
                            Text("auth required", comment: "Small label to indicate auth is required").font(.system(size: 12.0))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .background(.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .layoutPriority(5)
                        }
                    }
                    .id(relay.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Only allow selections when we are not .publishing already
                        guard viewState == .selecting else { return }
                        
                        // Only change from selected <-> unselected
                        // Don't change when its other state (.published / .error etc)
                        if let relayState = relayStates[relay], relayState == .selected {
                            relayStates[relay] = .unselected
                        }
                        else if let relayState = relayStates[relay], relayState == .unselected {
                            relayStates[relay] = .selected
                        }
                    }
                }
                
                
                NavigationLink {
                    EnterRelayAddressSheet(onAdd: { relayUrlString in
                        self.addRelay(relayUrlString)
                    })
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(Color.secondary)
                        Text("Enter new relay address...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            Section {
                Button(action: {
                    viewState = .publishing
                    Task {
                        await republishWithAuth()
                    }
                }, label: {
                    switch viewState {
                    case .publishing, .loading:
                        ProgressView()
                    case .selecting:
                        Text("Republish")
                    }
                })
                .buttonStyleGlassProminent()
                .disabled(signingAccount == nil || viewState == .publishing || (relayStates.count(where: { $0.value == .selected }) == 0))
                .frame(maxWidth: .infinity, alignment: .center)
            } footer: {
                if let signingAccount {
                    Text("Authenticating with account: \(signingAccount.anyName)")
                        .font(.footnote)
                        .foregroundColor(Color.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                else {
                    Text("Cannot find account to authenticate with")
                        .font(.footnote)
                        .foregroundColor(Color.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            if !logs.isEmpty {
                Section {
                    Text(logs)
                        .font(.footnote)
                        .foregroundColor(Color.gray)
                }
            }
        }
        
        .navigationTitle("Republish to relays")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    rootDismiss?()
                }
            }
        }
        
        .task {
            guard viewState == .loading else { return }
            let cloudRelays: [RelayData] = await bg().perform {
                return CloudRelay.fetchAll(context: bg()).map { $0.toStruct() }
            }
            
            self.relays = cloudRelays
            self.relayStates = Dictionary(uniqueKeysWithValues: cloudRelays.map { relay in (relay, .unselected) })
            viewState = .selecting
        }
        
        .onAppear {
            
            // Resolve signing account
            // sign with same key as post.pubkey if we have it, else sign with logged in account key
            let accountPubkey = account()?.publicKey ?? AccountsState.shared.activeAccountPublicKey
            let signPubkey = if AccountsState.shared.bgFullAccountPubkeys.contains(nrPost.pubkey) {
                nrPost.pubkey
            } else {
                accountPubkey
            }
            signingAccount = AccountsState.shared.accounts.first(where: { $0.publicKey == signPubkey })
            signingAccountPubkey = signingAccount?.publicKey ?? AccountsState.shared.activeAccountPublicKey
        }
        
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .navigationTitle("Republish post")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func addRelay(_ relayUrlString: String) {
        let relayData = RelayData.new(url: relayUrlString)
        
        var updatedRelays = self.relays
        updatedRelays.append(relayData)
        
        withAnimation {
            self.relays = updatedRelays
            self.relayStates[relayData] = .selected
        }
    }
    
    private func republishWithAuth() async {
        let nEvent: NEvent? = await withBgContext { _ in
            return nrPost.event?.toNEvent()
        }
        guard let nEvent else { return }
        
        let selectedRelays = relayStates.compactMap { (relay, state) in
            state == .selected ? relay : nil
        }
        
        // Set all selected relays to publishing state
        for relay in selectedRelays {
            relayStates[relay] = .publishing
        }
        
        // Publish to all relays simultaneously
        await withTaskGroup(of: (RelayData, RelayState).self) { group in
            for relay in selectedRelays {
                group.addTask {
                    do {
                        let connection = OneOffEventPublisher(relay.url, allowAuth: true, signNEventHandler: { unsignedEvent in
                            guard let signingAccountPubkey else { throw SignError.accountNotFound }
                            // sign with same key as post.pubkey if we have it, else sign with logged in account key
                            return try await sign(nEvent: unsignedEvent, accountPubkey: signingAccountPubkey)
                        })
                        
                        try await connection.connect(timeout: 6)
                        try await connection.publish(nEvent, timeout: 6)
                        
                        return (relay, RelayState.published)
                    } catch let myError as SendMessageError {
                        if case .sendFailed(let reason) = myError {
                            if let reason {
                                logs = logs + "\(reason)\n"
                            }
                            return (relay, RelayState.error)
                        }
                        else if case .authRequired = myError {
                            return (relay, RelayState.error)
                        }
                        return (relay, RelayState.error)
                    }
                    catch {
                        return (relay, RelayState.error)
                    }
                }
            }
            
            // Update relay states as tasks complete
            for await (relay, state) in group {
                relayStates[relay] = state
            }
        }

        viewState = .selecting
    }
}

enum RelayState {
    case unselected
    case selected
    case publishing
    case published
    case error
    case authRequired
}

struct RelayStateCheckbox: View {
    @Environment(\.theme) private var theme
    
    let relayState: RelayState
    
    var body: some View {
        switch relayState {
        case .unselected:
            Image(systemName: "circle")
                .foregroundColor(Color.secondary)
        case .selected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(theme.accent)
        case .publishing:
            ProgressView()
        case .published:
            Image(systemName: "checkmark")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "multiply.circle.fill")
                .foregroundColor(.red)
        case .authRequired:
            Image(systemName: "multiply.circle.fill")
                .foregroundColor(.red)
        }
    }
}


struct EnterRelayAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var relayAddress: String = "wss://"

    var onAdd: (String) -> Void
    
    var body: some View {
        NXForm {
            Section("Enter relay address") {
                TextField(text: $relayAddress, prompt: Text("wss://")) {
                    Text("Enter relay address")
                }
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add") {
                    // TODO: add validation
                    onAdd(relayAddress)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NBNavigationStack {
        RepublishRestrictedPostSheet(
            nrPost: testNRPost(###"{"tags":[["-"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"pubkey":"b55ca1f1aa95d5dc45877b8331a9598c53e38ef4a7bc436d765b11d660fc39c9","content":"Test","sig":"57ff038f6351ce6a38de306c38b0571b7dec6bc495e66503b07cd435852fa14aafc2b0c470a0366c859b87ffbe7e996f1caa5a43546c7aa84e577c8d4b2b4459","kind":1,"id":"10a6c4d9cf0baeda0a4195834fb6a99b8ed33378da5dc9fd3bba3a4f332b9f50","created_at":1756556200}"###)
        )
        .environment(\.theme, Themes.GREEN)
    }
}
