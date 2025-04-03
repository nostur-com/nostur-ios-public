//
//  RelayEditView.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/01/2023.
//

import SwiftUI
import Combine
import NostrEssentials

struct RelayEditView: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var relay: CloudRelay
    @ObservedObject private var cp: ConnectionPool = .shared
    @State private var connection: RelayConnection?
    @State private var refresh: Bool = false
    @State private var confirmRemoveShown = false
    @State private var relayUrl = ""
    
    @State private var excludedPubkeys: Set<String> = []
    private var accounts: [CloudAccount] {
        AccountsState.shared.accounts
            .sorted(by: { $0.publicKey < $1.publicKey })
            .filter { $0.isFullAccount }
    }
    
    @State private var isConnected: Bool = false
    @State private var connectedSub: AnyCancellable? = nil
    
    private func toggleAccount(_ account: CloudAccount) {
        if excludedPubkeys.contains(account.publicKey) {
            excludedPubkeys.remove(account.publicKey)
        }
        else {
            excludedPubkeys.insert(account.publicKey)
        }
    }
    
    private func isExcluded(_ account: CloudAccount) -> Bool {
        return excludedPubkeys.contains(account.publicKey)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Relay URL", comment: "Relay URL header") ) {
                TextField(String(localized:"wss://nostr.relay.url.here", comment:"Placeholder for entering a relay URL"), text: $relayUrl)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
            }
            .onChange(of: relayUrl) { newValue in
                guard relayUrl != newValue else { return } // same url
                guard newValue != connection?.url else { return } // init from "" to socket.url
                connection?.disconnect()
            }
            .listRowBackground(themes.theme.background)
            
            Section(header: Text("Relay settings", comment: "Relay settings header") ) {
                Toggle(isOn: $relay.auth) {
                    Text("Enable authentication", comment: "Label for toggle to enable AUTH on this relay")
                    Text("May be required to access special features on this relay")
                }
                Toggle(isOn: $relay.search) {
                    Text("Use relay for looking up posts", comment: "Label for toggle to look up posts on this relay")
                    Text("If a post can't be found on receiving relays, try to find the post on this relay")
                }
                Toggle(isOn: $relay.read) {
                    Text("Receive from this relay", comment: "Label for toggle to receive from this relay")
                }
                Toggle(isOn: $relay.write) {
                    Text("Publish to this relay", comment: "Label for toggle to publish to this relay") .background(refresh ? Color.clear : Color.clear)
                    if relay.write && accounts.count > 1 {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(accounts) { account in
                                    PFP(pubkey: account.publicKey, account: account, size: 30)
                                        .onTapGesture {
                                            toggleAccount(account)
                                        }
                                        .opacity(isExcluded(account) ? 0.25 : 1.0)
                                }
                            }
                        }
                        Text("Tap account to exclude")
                    }
                }
            }
            .listRowBackground(themes.theme.background)
            
            Section(header: Text("Status", comment: "Connection status header") ) {
                HStack {
                    if (isConnected) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.green)
                            .opacity(1)
                        Text("Connected", comment: "Relay status when connected")
                        Spacer()
                        Button {
                            connection?.disconnect()
                        } label: {
                            Text("Disconnect", comment: "Button to disconnect from relay")
                        }
                    }
                    else {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.gray)
                            .opacity(0.2)
                        Text("Disconnected", comment: "Relay status when disconnected")
                        Spacer()
                        Button {
                            let correctedRelayUrl = normalizeRelayUrl(relayUrl)
                            relayUrl = correctedRelayUrl
                            if (connection?.url != correctedRelayUrl) { // url change?
                                connection?.disconnect()
                                
                                // Replace the connection first
                                if let oldUrl = relay.url_ {
                                    ConnectionPool.shared.removeConnection(oldUrl.lowercased())
                                    ConnectionPool.shared.removeConnection(correctedRelayUrl)
                                }
                                let newRelayData = RelayData.new(url: correctedRelayUrl, read: relay.read, write: relay.write, search: relay.search, auth: relay.auth, excludedPubkeys:  relay.excludedPubkeys)
                                
                                ConnectionPool.shared.addConnection(newRelayData) { replacedConnection in
                                    Task { @MainActor in
                                        connection = replacedConnection
                                        // Then connect (force)
                                        connection?.connect(forceConnectionAttempt: true)
                                        
                                        isConnected = replacedConnection.isConnected
                                        connectedSub?.cancel()
                                        connectedSub = replacedConnection.objectWillChange.sink { _ in
                                            Task { @MainActor in
                                                isConnected = replacedConnection.isConnected
                                            }
                                        }
                                    }
                                }
                            }
                            else {
                                // Then connect (force)
                                connection?.connect(forceConnectionAttempt: true)
                            }
                            
                            
                        } label: {
                            Text("Connect", comment: "Button to connect to relay")
                        }
                    }
                }
            }
            .listRowBackground(themes.theme.background)
            
            Section(header: Text("")) {
                Text("Remove")
                    .foregroundColor(.red)
                    .onTapGesture {
                        confirmRemoveShown = true
                    }
                .hCentered()
                
                .confirmationDialog("Remove this relay: \(relay.url_ ?? "")?", isPresented: $confirmRemoveShown, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        connection?.disconnect()
                        if let oldUrl = relay.url_ {
                            ConnectionPool.shared.removeConnection(oldUrl.lowercased())
                        }
                        viewContext.delete(relay)
                        dismiss()
                        do {
                            try viewContext.save()
                            L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
                        } catch {
                            L.og.error("could not save after removing relay")
                        }
                    }
                }
            }
            .listRowBackground(themes.theme.background)
        }
        .scrollContentBackgroundHidden()
        .navigationTitle(String(localized:"Edit relay", comment:"Navigation title for Edit relay screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    do {
                        let correctedRelayUrl = normalizeRelayUrl((relayUrl.prefix(6) != "wss://" && relayUrl.prefix(5) != "ws://"  ? ("wss://" + relayUrl) : relayUrl).lowercased())
                        relayUrl = correctedRelayUrl
                        relay.url_ = correctedRelayUrl
                        relay.excludedPubkeys = excludedPubkeys
                        relay.updatedAt = .now
                        try viewContext.save()
                        L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
                        // Update existing connections
                        // url change?
                        if (connection?.url != correctedRelayUrl) {
                            connection?.disconnect()
                            if let oldUrl = connection?.url {
                                ConnectionPool.shared.removeConnection(oldUrl.lowercased())
                            }
                            let newRelayData = RelayData.new(url: correctedRelayUrl, read: relay.read, write: relay.write, search: relay.search, auth: relay.auth, excludedPubkeys: relay.excludedPubkeys)
                            let read = relay.read
                            ConnectionPool.shared.addConnection(newRelayData) { relayConnection in
                                if read {
                                    relayConnection.connect()
                                }
                                Task { @MainActor in
                                    connection = relayConnection
                                    
                                    isConnected = relayConnection.isConnected
                                    connectedSub?.cancel()
                                    connectedSub = relayConnection.objectWillChange.sink { _ in
                                        Task { @MainActor in
                                            isConnected = relayConnection.isConnected
                                        }
                                    }
                                }
                            }
                        }
                        else {
                            // read/write/exclude change?
                            connection?.relayData.setRead(relay.read)
                            connection?.relayData.setWrite(relay.write)
                            connection?.relayData.setAuth(relay.auth)
                            connection?.recentAuthAttempts = 0 // reset or it won't try to auth because of previous failed attempts
                            connection?.relayData.setExcludedPubkeys(relay.excludedPubkeys)
                            
                            if let connection {
                                isConnected = connection.isConnected
                                connectedSub?.cancel()
                                connectedSub = connection.objectWillChange.sink { _ in
                                    Task { @MainActor in
                                        isConnected = connection.isConnected
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        L.og.error("problem ")
                    }
                    dismiss()
                }
            }
        }
        .onChange(of: relay.read) { newValue in
            if let connection = connection, connection.relayData.read != newValue {
                connection.relayData.setRead(newValue)
            }
        }
        .onChange(of: relay.write) { newValue in
            if let connection = connection, connection.relayData.write != newValue {
                connection.relayData.setWrite(newValue)
            }
        }
        .onChange(of: relay.auth) { newValue in
            if let connection = connection, connection.relayData.auth != newValue {
                connection.relayData.setAuth(newValue)
                connection.recentAuthAttempts = 0 // reset or it won't try to auth because of previous failed attempts
            }
        }
        .onAppear {
            relayUrl = relay.url_ ?? ""
            excludedPubkeys = relay.excludedPubkeys
            Task {
                if let conn = await ConnectionPool.shared.getConnection(relayUrl.lowercased()) {
                    Task { @MainActor in
                        connection = conn
                        
                        isConnected = conn.isConnected
                        connectedSub?.cancel()
                        connectedSub = conn.objectWillChange.sink { _ in
                            Task { @MainActor in
                                isConnected = conn.isConnected
                            }
                        }
                    }
                }
            }
        }
        .onReceive(cp.objectWillChange, perform: { _ in
            Task {
                if let conn = await ConnectionPool.shared.getConnection(relayUrl.lowercased()) {
                    Task { @MainActor in
                        connection = conn
                        
                        isConnected = conn.isConnected
                        connectedSub?.cancel()
                        connectedSub = conn.objectWillChange.sink { _ in
                            Task { @MainActor in
                                isConnected = conn.isConnected
                            }
                        }
                    }
                }
            }
        })
    }
}

import NavigationBackport

struct RelayEditView_Previews: PreviewProvider {
    
    static var previews: some View {
        let relay = CloudRelay(context: DataProvider.shared().container.viewContext)
        relay.url_ = "ws://localhost:3000"
        relay.read = true
        relay.write = false
        relay.auth = false
        relay.createdAt = Date()
        
        return NBNavigationStack {
            PreviewContainer({ pe in pe.loadAccounts() }) {
                RelayEditView(relay: relay)
            }
        }
    }
}
