//
//  RepublishPostSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/09/2025.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

// broadcast any post, doesn't necessarily need auth
// tries first without auth
// but when relays come back with auth-required, will offer to retry with auth
struct RepublishPostSheet: View {
    @Environment(\.theme) private var theme
    
    @ObservedObject public var nrPost: NRPost // Should be non-restricted ["-"] post, use check in container, not this view
    public var rootDismiss: DismissAction
    
    @State private var relays: [RelayData] = []
    
    enum ViewState {
        case loading // needed or .task { } will rerun when navigating back
        case selecting
        case publishing
        case selectingAuthRequired
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
                        guard viewState == .selecting || viewState == .selectingAuthRequired else { return }
                        
                        // Only change from selected <-> unselected (or auth req -> unselected)
                        // Don't change when its other state (.published / .error etc)
                        if let relayState = relayStates[relay], (relayState == .selected || relayState == .authRequired) {
                            relayStates[relay] = .unselected
                        }
                        else if let relayState = relayStates[relay], relayState == .unselected {
                            relayStates[relay] = .selected
                        }
                        
                        if viewState == .selectingAuthRequired { // when deselecting failed auth required, revert publish button back to normal
                            if relayStates.count(where: { $0.value == .authRequired }) == 0 {
                                viewState = .selecting
                            }
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
                    let allowAuth = viewState == .selectingAuthRequired // Need state before we change it
                    viewState = .publishing
                    Task {
                        await republish(allowAuth: allowAuth)
                    }
                }, label: {
                    switch viewState {
                    case .publishing, .loading:
                        ProgressView()
                    case .selecting:
                        Text("Republish")
                    case .selectingAuthRequired:
                        Text("Retry with authentication")
                    }
                })
                .disabled(viewState == .publishing || (relayStates.count(where: { $0.value == .selected }) == 0 && relayStates.count(where: { $0.value == .authRequired }) == 0))
                .frame(maxWidth: .infinity, alignment: .center)
            } footer: {
                if viewState == .selectingAuthRequired {
                    if let signingAccount {
                        Text("Using account: \(signingAccount.anyName)")
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
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    rootDismiss()
                }
            }
        }
        
        .task {
            guard viewState == .loading else { return }
            let cloudRelays: [RelayData] = await bg().perform {
                return CloudRelay.fetchAll(context: bg()).map { $0.toStruct() }
            }
            
            self.relays = cloudRelays
            self.relayStates = Dictionary(uniqueKeysWithValues: cloudRelays.map { relay in
                if relay.write {
                    return (relay, .selected)
                }
                return (relay, .unselected)
            })
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
    
    private func republish(allowAuth: Bool = false) async {
        let nEvent: NEvent? = await withBgContext { _ in
            return nrPost.event?.toNEvent()
        }
        guard let nEvent else { return }
        
        
        let selectedRelays = if allowAuth { // try only once that failed with auth required
            relayStates.compactMap { (relay, state) in
                state == .authRequired ? relay : nil
            }
        } else { // try normal selection
            relayStates.compactMap { (relay, state) in
                state == .selected ? relay : nil
            }
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
                        // TODO: don't need OneOffEventPublisher for already connected write relays
                        
                        let connection = OneOffEventPublisher(relay.url, allowAuth: allowAuth || relay.auth, signNEventHandler: { unsignedEvent in
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
                            return (relay, RelayState.authRequired)
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
        
        if relayStates.count(where: { $0.value == .authRequired }) != 0 {
            viewState = .selectingAuthRequired
        }
        else {
            viewState = .selecting
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @Environment(\.dismiss) var dismiss
    
    NBNavigationStack {
        RepublishPostSheet(
            nrPost: testNRPost(###"{"sig":"9334ba6c53acf23dd83b27cd3ebdec333a7a9e11001884c3bc0a2e71114738621f2a0a87507fdf215fc1540e53626b3a90034e242e93a65414062204ae22b947","content":"https://media.utxo.nl/wp-content/uploads/nostr/d/f/dfbbd8dd736b31c32c6d26d24081c6984c0784d5ad43bd95050e97e2b6e0e83d.webp\nGM","id":"b1307ffcb88ffa28b2dacbf0bd1bcee88d24b64798a570851fb05c51fa46e327","tags":[["imeta","url https://media.utxo.nl/wp-content/uploads/nostr/d/f/dfbbd8dd736b31c32c6d26d24081c6984c0784d5ad43bd95050e97e2b6e0e83d.webp","dim 2338x2338","sha256 dfbbd8dd736b31c32c6d26d24081c6984c0784d5ad43bd95050e97e2b6e0e83d"],["k","20"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"kind":1,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1756714070}"###),
            rootDismiss: dismiss
        )
        .environment(\.theme, Themes.GREEN)
    }
}
