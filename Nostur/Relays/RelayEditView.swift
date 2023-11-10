//
//  RelayEditView.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/01/2023.
//

import SwiftUI

struct RelayEditView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var relay: Relay
    @ObservedObject var socket: NewManagedClient
    @State private var refresh: Bool = false
    @ObservedObject private var sp:SocketPool = .shared
    @State private var confirmRemoveShown = false
    @State private var relayUrl =  ""
    
    @State private var excludedPubkeys:Set<String> = []
    private var accounts:[CloudAccount] {
        NRState.shared.accounts
            .sorted(by: { $0.publicKey < $1.publicKey })
            .filter { $0.privateKey != nil }
    }
    
    private var isConnected:Bool {
        edittingSocket?.isConnected ?? false
    }
    
    private var edittingSocket:NewManagedClient? {
        let managedClient = sp.sockets.filter { relayId, managedClient in
            managedClient.url == relayUrl.lowercased()
        }.first?.value
        return managedClient
    }
    
    private func toggleAccount(_ account:CloudAccount) {
        if excludedPubkeys.contains(account.publicKey) {
            excludedPubkeys.remove(account.publicKey)
        }
        else {
            excludedPubkeys.insert(account.publicKey)
        }
    }
    
    private func isExcluded(_ account:CloudAccount) -> Bool {
        return excludedPubkeys.contains(account.publicKey)
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack {
            Form {
                Section(header: Text("Relay URL", comment: "Relay URL header") ) {
                    TextField(String(localized:"wss://nostr.relay.url.here", comment:"Placeholder for entering a relay URL"), text: $relayUrl)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                .onChange(of: relayUrl) { newValue in
                    guard relayUrl != newValue else { return } // same url
                    guard newValue != edittingSocket?.url else { return } // init from "" to socket.url
                    edittingSocket?.disconnect()
                }
                Section(header: Text("Relay settings", comment: "Relay settings header") ) {
                    Toggle(isOn: $relay.read) {
                        Text("Receive from this relay", comment: "Label for toggle to receive from this relay")
                    }
                    Toggle(isOn: $relay.write) {
                        Text("Publish to this relay", comment: "Label for toggle to publish to this relay") .background(refresh ? Color.clear : Color.clear)
                        if relay.write {
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
                Section(header: Text("Status", comment: "Connection status header") ) {
                    HStack {
                        if (isConnected) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .opacity(1)
                            Text("Connected", comment: "Relay status when connected")
                            Spacer()
                            Button {
                                edittingSocket?.disconnect()
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
                                // url change?
                                if (edittingSocket?.url != relayUrl) {
                                    edittingSocket?.client.disconnect()
                                    sp.removeSocket(relay.objectID)
                                    let replacedSocket = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relayUrl, read: relay.read, write: relay.write, excludedPubkeys: excludedPubkeys)
                                    replacedSocket.connect(true)
//                                    replacedSocket.client.connect()
                                }
                                edittingSocket?.connect(true)
//                                edittingSocket?.client.connect()
                            } label: {
                                Text("Connect", comment: "Button to connect to relay")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized:"Edit relay", comment:"Navigation title for Edit relay screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button {
                    confirmRemoveShown = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .confirmationDialog("Remove this relay: \(relay.url ?? "")?", isPresented: $confirmRemoveShown, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        socket.client.disconnect()
                        sp.removeSocket(relay.objectID)
                        viewContext.delete(relay)
                        edittingSocket?.disconnect()
                        dismiss()
                        do {
                            try viewContext.save()
                        } catch {
                            L.og.error("could not save after removing relay")
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    do {
                        let correctedRelayUrl = (relayUrl.prefix(6) != "wss://" && relayUrl.prefix(5) != "ws://"  ? ("wss://" + relayUrl) : relayUrl).lowercased()
                        relay.url = correctedRelayUrl
                        relay.excludedPubkeys = excludedPubkeys
                        try viewContext.save()
                        // Update existing connections
                        // url change?
                        if (socket.url != correctedRelayUrl) {
                            socket.client.disconnect()
                            sp.removeSocket(relay.objectID)
                            _ = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: correctedRelayUrl, read: relay.read, write: relay.write, excludedPubkeys: excludedPubkeys)
                        }
                        else {
                            // read/write/exclude change?
                            socket.write = relay.write
                            socket.read = relay.read
                            socket.excludedPubkeys = excludedPubkeys
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
            socket.read = newValue
        }
        .onChange(of: relay.write) { newValue in
            socket.write = newValue
        }
        .onAppear {
            relayUrl = relay.url ?? ""
            excludedPubkeys = relay.excludedPubkeys
        }
    }
}

struct RelayEditView_Previews: PreviewProvider {
    
    static var previews: some View {
        let relay = Relay(context: DataProvider.shared().container.viewContext)
        relay.id = UUID()
        relay.url = "ws://localhost:3000"
        relay.read = true
        relay.write = false
        relay.createdAt = Date()
        
        let sp:SocketPool = .shared
        
        func socketForRelay(relay: Relay) -> NewManagedClient {
            guard let socket = sp.sockets[relay.objectID.uriRepresentation().absoluteString] else {
                let addedSocket = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relay.url!, read: relay.read, write: relay.write)
                return addedSocket
            }
            return socket
        }
        
        return NavigationStack {
            PreviewContainer({ pe in pe.loadAccounts() }) {
                RelayEditView(relay: relay, socket: socketForRelay(relay: relay))
            }
        }
    }
}
