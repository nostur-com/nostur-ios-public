//
//  CustomNWCConnectSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/06/2023.
//

import SwiftUI
import NostrEssentials
import UIKit

struct CustomNWCConnectSheet: View {
    @Environment(\.theme) private var theme
    @State var awaitingConnectionId = ""
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    @State var nwcConnectSuccess = false
    @State var showDisconnect = false
    @ObservedObject var ss: SettingsStore = .shared
    @State var nwcUri = ""
    @State var tryingConnection = false
    @State var nwcErrorMessage = ""
    @State var connectionTimeout:Timer? = nil
    @State var showQRScanner = false
    
    var validUri: Bool {
        if let _ = try? NWCURI(string: nwcUri) {
            return true
        }
        return false
    }
    
    var body: some View {
        VStack {
            if (nwcConnectSuccess) {
                Text("Your wallet is now connected with **Nostur**, you can now enjoy a seamless zapping experience!")
                    .multilineTextAlignment(.center)
                    .padding(10)
            }
            else {
                Text("Connect your NWC compatible wallet with **Nostur** for a seamless zapping experience")
                    .multilineTextAlignment(.center)
                    .padding(10)
                
            }
            
            if (nwcConnectSuccess) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.green)
                    .frame(height: 75)
                    .onTapGesture {
                        dismiss()
                    }
                
                if showDisconnect {
                    Button((String(localized:"Disconnect", comment:"Button to disconnect NWC (Nostr Wallet Connection)")), role: .destructive) {
                        removeExistingNWCsocket()
                        ss.activeNWCconnectionId = ""
                        showDisconnect = false
                        nwcConnectSuccess = false
                    }
                }
            }
            else {
                
                Text("Nostr Wallet Connect URI", comment: "Label for entering Nostr Wallet Connect URI")
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 20)
                
                TextField("", text: $nwcUri, prompt: Text(verbatim: "nostrwalletconnect:..."))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.top, 0)
                    .padding(.horizontal, 10)
                
                HStack {
                    if canScanQRCode {
                        Button(String(localized: "Scan QR", comment: "Button to scan a QR code for Nostr Wallet Connect setup"), systemImage: "qrcode.viewfinder") {
                            showQRScanner = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(String(localized: "Paste", comment: "Button to paste a Nostr Wallet Connect URI from the clipboard"), systemImage: "doc.on.clipboard") {
                        pasteNWCURIFromClipboard()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                
                if !nwcErrorMessage.isEmpty {
                    Text(nwcErrorMessage).fontWeight(.bold).foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                
                if !nwcErrorMessage.isEmpty && !awaitingConnectionId.isEmpty {
                    Button("Try to use anyway") {
                        DispatchQueue.main.async {
                            ss.activeNWCconnectionId = awaitingConnectionId
                            nwcConnectSuccess = true
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                if !tryingConnection {
                    Button(String(localized:"Connect wallet", comment: "Button to connect a wallet to Nostur")) { startNWC() }
                        .buttonStyle(NRButtonStyle(style: .borderedProminent))
                        .disabled(!validUri)
                }
                else {
                    ProgressView()
                        .padding()
                }
                
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle((String(localized:"Nostr Wallet Connect", comment:"Navigation title for setting up Nostr Wallet Connect (NWC)")))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if nwcConnectSuccess {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .buttonStyleGlassProminent()
                }
            }
        
            ToolbarItem(placement: .cancellationAction) {
                if !nwcConnectSuccess {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .onAppear {
            if !ss.activeNWCconnectionId.isEmpty, let nwc = NWCConnection.fetchConnection(ss.activeNWCconnectionId, context: DataProvider.shared().viewContext), nwc.type == "CUSTOM" {
                
                nwcConnectSuccess = true
                showDisconnect = true // Only show after opening again, because showing right after connecting is confusing
            }
            else {
                ss.activeNWCconnectionId = ""
            }
        }
        .onDisappear {
            cancelConnectionTimeout()
        }
        .onChange(of: nwcUri) { _ in
            if !nwcErrorMessage.isEmpty {
                nwcErrorMessage = ""
            }
        }
        .onReceive(receiveNotification(.nwcInfoReceived)) { notification in
            // Here we received the info event from the NWC relay
            let nwcInfoNotification = notification.object as! NWCInfoNotification
            
            bg().perform {
                if let _ = NWCConnection.fetchConnection(awaitingConnectionId, context: bg()) {
                    if nwcInfoNotification.methods.split(separator: " ").map({ String($0) }).contains("pay_invoice") {
                        DispatchQueue.main.async {
                            finishConnectionAttempt()
                            ss.activeNWCconnectionId = awaitingConnectionId
                            nwcConnectSuccess = true
                        }
                    }
                    // NIP47 spec says to uses space separator, but Alby uses comma.
                    else if nwcInfoNotification.methods.split(separator: ",").map({ String($0) }).contains("pay_invoice") {
                        DispatchQueue.main.async {
                            finishConnectionAttempt()
                            ss.activeNWCconnectionId = awaitingConnectionId
                            nwcConnectSuccess = true
                        }
                    }
                    else {
                        L.og.error("⚡️ NWC custom connection, does not support pay_invoice")
                        DispatchQueue.main.async {
                            tryingConnection = false
                            cancelConnectionTimeout()
                            nwcErrorMessage = String(localized:"This NWC connection does not support payments", comment: "Error message during NWC setup")
                        }
                    }
                    DataProvider.shared().saveToDiskNow(.bgContext)
                }
                else {
                    L.og.error("⚡️ NWC connection missing")
                }
            }
        }
        .sheet(isPresented: $showQRScanner) {
            NWCQRScannerSheet { scannedValue in
                importNWCURI(scannedValue, autoConnect: true)
            }
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
    
    func startNWC() {
        let normalizedUri = normalizeNWCURI(nwcUri)
        nwcUri = normalizedUri
        
        guard let nwc = try? NWCURI(string: normalizedUri),
              let secret = nwc.secret,
              let relay = nwc.relay,
              let walletPubkey = nwc.walletPubkey
        else {
            tryingConnection = false
            nwcErrorMessage = String(localized:"Problem parsing NWC connection URI", comment:"Error message during NWC setup")
            return
        }
        nwcErrorMessage = ""
        cancelConnectionTimeout()
        
        bg().perform {
            guard let c = NWCConnection.createCustomConnection(context: bg(), secret: secret) else {
                L.og.error("Problem handling secret in NWCConnection.createCustomConnection")
                DispatchQueue.main.async {
                    tryingConnection = false
                    nwcErrorMessage = String(localized: "Could not parse secret from NWC connection URI", comment: "Error message during NWC setup")
                }
                return
            }
            c.walletPubkey = walletPubkey
            c.relay = relay
            let connectionId = c.connectionId
            DispatchQueue.main.async {
                awaitingConnectionId = connectionId
                tryingConnection = true
            }
            
            removeExistingNWCsocket()
            DispatchQueue.main.async {
                L.og.info("⚡️ Adding NWC connection")
                ConnectionPool.shared.addNWCConnection(connectionId:connectionId, url: relay) { conn in
                    if !conn.isConnected {
                        conn.connect()
                    }
                }
                
                NWCRequestQueue.shared.nwcConnection = c
                Importer.shared.nwcConnection = c
                
                L.og.info("⚡️ Fetching 13194 (info) from NWC relay")
                ConnectionPool.shared
                    .sendMessage(
                        NosturClientMessage(
                            clientMessage: NostrEssentials.ClientMessage(
                                type: .REQ,
                                filters: [Filters(authors: [walletPubkey], kinds: [13194], limit: 1)]
                            ),
                            onlyForNWCRelay: true,
                            relayType: .READ
                        )
                    )
            }
        }
        
        connectionTimeout?.invalidate()
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false, block: { _ in
            tryingConnection = false
            nwcErrorMessage = String(localized:"Could not fetch NWC info event from \(relay)", comment:"Error message during NWC setup")
            connectionTimeout = nil
        })
    }
    
    func removeExistingNWCsocket() {
        var removeKey: String?
        ConnectionPool.shared.connections.values.forEach { connection in
            if connection.isNWC {
                connection.disconnect()
                removeKey = connection.url
            }
        }
        if let removeKey {
            ConnectionPool.shared.removeConnection(removeKey)
        }
        if !ss.activeNWCconnectionId.isEmpty {
            NWCConnection.delete(ss.activeNWCconnectionId, context: DataProvider.shared().viewContext)
        }
    }
    
    private var canScanQRCode: Bool {
#if targetEnvironment(macCatalyst)
        false
#else
        true
#endif
    }
    
    private func pasteNWCURIFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            nwcErrorMessage = String(localized: "Clipboard does not contain a Nostr Wallet Connect URI", comment: "Error shown when the clipboard has no Nostr Wallet Connect URI to paste")
            return
        }
        importNWCURI(
            clipboardText,
            autoConnect: false,
            invalidMessage: String(localized: "Clipboard does not contain a valid Nostr Wallet Connect URI", comment: "Error shown when pasted clipboard text is not a valid Nostr Wallet Connect URI")
        )
    }
    
    private func importNWCURI(_ rawValue: String, autoConnect: Bool, invalidMessage: String = String(localized: "Scanned QR code is not a valid Nostr Wallet Connect URI", comment: "Error shown when a scanned QR code is not a valid Nostr Wallet Connect URI")) {
        let normalizedUri = normalizeNWCURI(rawValue)
        nwcUri = normalizedUri
        nwcErrorMessage = ""
        
        guard validNWCURI(normalizedUri) else {
            nwcErrorMessage = invalidMessage
            return
        }
        
        if autoConnect {
            startNWC()
        }
    }
    
    private func validNWCURI(_ uri: String) -> Bool {
        (try? NWCURI(string: uri)) != nil
    }
    
    private func normalizeNWCURI(_ rawValue: String) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.lowercased().contains("nostrwalletconnect:") {
            let lines = trimmedValue
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let uriLine = lines.first(where: { $0.lowercased().contains("nostrwalletconnect:") }) {
                return uriLine
            }
        }
        return trimmedValue
    }
    
    private func cancelConnectionTimeout() {
        connectionTimeout?.invalidate()
        connectionTimeout = nil
    }
    
    private func finishConnectionAttempt() {
        tryingConnection = false
        cancelConnectionTimeout()
    }
}

import NavigationBackport

struct CustomNWCConnectSheet_Previews: PreviewProvider {
    static var previews: some View {
        NBNavigationStack {
            CustomNWCConnectSheet()
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
        .environmentObject(Themes.default)
    }
}

struct NWCInfoNotification: Identifiable {
    let id = UUID()
    let methods:String
}
