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
    @Environment(\.theme) private var theme
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
    @State private var connectionStatus: RelayStatus = .disconnected
    @State private var connectTimeoutTask: Task<Void, Never>? = nil
    @State private var relayInformation: RelayInformationDocument? = nil

    private enum RelayStatus: Equatable {
        case connected
        case disconnected
        case connecting
        case failed(String)
    }

    private var statusText: String {
        switch connectionStatus {
        case .connected:
            return String(localized: "Connected", comment: "Relay status when connected")
        case .disconnected:
            return String(localized: "Disconnected", comment: "Relay status when disconnected")
        case .connecting:
            return String(localized: "Connecting...", comment: "Relay status while connecting")
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch connectionStatus {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .failed:
            return .red
        case .disconnected:
            return .gray
        }
    }

    private var statusOpacity: Double {
        connectionStatus == .disconnected ? 0.2 : 1.0
    }

    @MainActor
    private func setConnectionState(_ connected: Bool) {
        isConnected = connected
        if connected {
            connectTimeoutTask?.cancel()
            connectionStatus = .connected
        }
        else if connectionStatus != .connecting, case .failed = connectionStatus {
            // Keep explicit failure feedback visible until the next user action.
        }
        else if connectionStatus != .connecting {
            connectionStatus = .disconnected
        }
    }

    @MainActor
    private func startConnectionAttempt() {
        connectTimeoutTask?.cancel()
        connectionStatus = .connecting
        connectTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, !isConnected, connectionStatus == .connecting else { return }
            connectionStatus = .failed(String(localized: "Connection timed out", comment: "Relay connection timeout status"))
        }
    }

    private func relayMessageMatchesCurrentRelay(_ message: String) -> Bool {
        let candidates = [connection?.url, relayUrl]
            .compactMap { $0 }
            .map { normalizeRelayUrl($0).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
        let lowerMessage = message.lowercased()

        for candidate in candidates {
            if lowerMessage.contains(candidate) {
                return true
            }
            if let host = URL(string: candidate)?.host?.lowercased(), lowerMessage.contains(host) {
                return true
            }
        }
        return false
    }

    private func errorText(fromSocketNotification message: String) -> String {
        let raw = message.replacingOccurrences(of: "Error:", with: "").trimmingCharacters(in: .whitespaces)
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return String(localized: "Connection failed", comment: "Relay connection failed status")
        }
        return String(parts[1])
    }
    
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

    private var relayInfoLookupUrl: String? {
        let raw = relayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "wss://", raw != "ws://" else { return nil }

        let normalized = normalizeRelayUrl(raw)
        guard let components = URLComponents(string: normalized),
              components.host != nil
        else {
            return nil
        }
        return normalized
    }
    
    var body: some View {
        NXForm {
            Section(header: Text("Relay URL", comment: "Relay URL header") ) {
                TextField(String(localized:"wss://nostr.relay.url.here", comment:"Placeholder for entering a relay URL"), text: $relayUrl)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
            }
            .onChange(of: relayUrl) { [oldValue = self.relayUrl] newValue in
                guard oldValue != newValue else { return } // same url
                guard newValue != connection?.url else { return } // init from "" to socket.url
                connection?.disconnect()
            }
            .listRowBackground(theme.background)
            
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
            .listRowBackground(theme.background)
            
            Section(header: Text("Status", comment: "Connection status header") ) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(statusColor)
                        .opacity(statusOpacity)
                    Text(statusText)
                    Spacer()
                    if (isConnected) {
                        Button {
                            connectTimeoutTask?.cancel()
                            connectionStatus = .disconnected
                            connection?.disconnect()
                        } label: {
                            Text("Disconnect", comment: "Button to disconnect from relay")
                        }
                        .padding(.trailing, 8)
                    }
                    else {
                        Button {
                            if !NetworkMonitor.shared.isConnected {
                                connectionStatus = .failed(String(localized: "No internet connection", comment: "Relay no internet status"))
                                return
                            }
                            Task { @MainActor in
                                startConnectionAttempt()
                            }
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
                                        
                                        setConnectionState(replacedConnection.isConnected)
                                        connectedSub?.cancel()
                                        connectedSub = replacedConnection.objectWillChange.sink { _ in
                                            Task { @MainActor in
                                                setConnectionState(replacedConnection.isConnected)
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
                        .padding(.trailing, 8)
                    }
                }
            }
            .listRowBackground(theme.background)

            if let relayInfoLookupUrl, relayInformation != nil {
                Section(header: Text("Relay information")) {
                    RelayInformationCard(relayUrl: relayInfoLookupUrl)
                }
                .listRowBackground(theme.background)
            }
            
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
#if DEBUG
                            L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
#endif
                        } catch {
#if DEBUG
                            L.og.error("could not save after removing relay")
#endif
                        }
                    }
                }
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundHidden()
        .navigationTitle(String(localized:"Edit relay", comment:"Navigation title for Edit relay screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save", systemImage: "checkmark") {
                    do {
                        let correctedRelayUrl = normalizeRelayUrl((relayUrl.prefix(6) != "wss://" && relayUrl.prefix(5) != "ws://"  ? ("wss://" + relayUrl) : relayUrl).lowercased())
                        relayUrl = correctedRelayUrl
                        relay.url_ = correctedRelayUrl
                        relay.excludedPubkeys = excludedPubkeys
                        relay.updatedAt = .now
                        try viewContext.save()
#if DEBUG
                        L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
#endif
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
                                    
                                    setConnectionState(relayConnection.isConnected)
                                    connectedSub?.cancel()
                                    connectedSub = relayConnection.objectWillChange.sink { _ in
                                        Task { @MainActor in
                                            setConnectionState(relayConnection.isConnected)
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
                                setConnectionState(connection.isConnected)
                                connectedSub?.cancel()
                                connectedSub = connection.objectWillChange.sink { _ in
                                    Task { @MainActor in
                                        setConnectionState(connection.isConnected)
                                    }
                                }
                            }
                        }
                    }
                    catch {
#if DEBUG
                        L.og.error("problem ")
#endif
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
                        
                        setConnectionState(conn.isConnected)
                        connectedSub?.cancel()
                        connectedSub = conn.objectWillChange.sink { _ in
                            Task { @MainActor in
                                setConnectionState(conn.isConnected)
                            }
                        }
                    }
                }
            }
        }
        .task(id: relayInfoLookupUrl) {
            guard let relayInfoLookupUrl else {
                relayInformation = nil
                return
            }
            relayInformation = await fetchRelayInformationDocument(for: relayInfoLookupUrl)
        }
        .onReceive(cp.objectWillChange, perform: { _ in
            Task {
                if let conn = await ConnectionPool.shared.getConnection(relayUrl.lowercased()) {
                    Task { @MainActor in
                        connection = conn
                        
                        setConnectionState(conn.isConnected)
                        connectedSub?.cancel()
                        connectedSub = conn.objectWillChange.sink { _ in
                            Task { @MainActor in
                                setConnectionState(conn.isConnected)
                            }
                        }
                    }
                }
            }
        })
        .onReceive(receiveNotification(.socketNotification)) { notification in
            guard let message = notification.object as? String else { return }
            guard relayMessageMatchesCurrentRelay(message) else { return }
            if message.starts(with: "Error:") {
                connectTimeoutTask?.cancel()
                connectionStatus = .failed(errorText(fromSocketNotification: message))
            }
            else if !isConnected {
                if connectionStatus == .connecting {
                    connectionStatus = .failed(String(localized: "Connection failed", comment: "Relay generic connection failed status"))
                }
                else {
                    connectionStatus = .disconnected
                }
            }
        }
        .onReceive(receiveNotification(.socketConnected)) { notification in
            guard let message = notification.object as? String else { return }
            guard relayMessageMatchesCurrentRelay(message) else { return }
            Task { @MainActor in
                setConnectionState(true)
            }
        }
        .onDisappear {
            connectTimeoutTask?.cancel()
        }
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
