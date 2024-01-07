//
//  CustomNWCConnectSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/06/2023.
//

import SwiftUI

struct CustomNWCConnectSheet: View {
    @EnvironmentObject private var themes:Themes
    @State var awaitingConnectionId = ""
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    @State var nwcConnectSuccess = false
    @State var showDisconnect = false
    @ObservedObject var ss:SettingsStore = .shared
    @State var nwcUri = ""
    @State var tryingConnection = false
    @State var nwcErrorMessage = ""
    @State var connectionTimeout:Timer? = nil
    
    var validUri:Bool {
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
                    .padding(.top, 0)
                    .padding(.horizontal, 10)
                
                if !nwcErrorMessage.isEmpty {
                    Text(nwcErrorMessage).fontWeight(.bold).foregroundColor(.red)
                    Button("Try to use anyway") {
                        DispatchQueue.main.async {
                            ss.activeNWCconnectionId = awaitingConnectionId
                            nwcConnectSuccess = true
                        }
                    }
                }
                else {
                    if !tryingConnection {
                        Button(String(localized:"Connect wallet", comment: "Button to connect a wallet to Nostur")) { startNWC() }
                            .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                            .disabled(!validUri)
                    }
                    else {
                        ProgressView()
                            .padding()
                    }
                }
                
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle((String(localized:"Nostr Wallet Connect", comment:"Navigation title for setting up Nostr Wallet Connect (NWC)")))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if nwcConnectSuccess {
                    Button("Done") { dismiss() }
                }
            }
        
            ToolbarItem(placement: .cancellationAction) {
                if !nwcConnectSuccess {
                    Button("Cancel") { dismiss() }
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
        .onReceive(receiveNotification(.nwcInfoReceived)) { notification in
            // Here we received the info event from the NWC relay
            let nwcInfoNotification = notification.object as! NWCInfoNotification
            
            bg().perform {
                if let _ = NWCConnection.fetchConnection(awaitingConnectionId, context: bg()) {
                    if nwcInfoNotification.methods.split(separator: " ").map({ String($0) }).contains("pay_invoice") {
                        DispatchQueue.main.async {
                            ss.activeNWCconnectionId = awaitingConnectionId
                            nwcConnectSuccess = true
                        }
                    }
                    // NIP47 spec says to uses space separator, but Alby uses comma.
                    else if nwcInfoNotification.methods.split(separator: ",").map({ String($0) }).contains("pay_invoice") {
                        DispatchQueue.main.async {
                            ss.activeNWCconnectionId = awaitingConnectionId
                            nwcConnectSuccess = true
                        }
                    }
                    else {
                        L.og.error("⚡️ NWC custom connection, does not support pay_invoice")
                        nwcErrorMessage = String(localized:"This NWC connection does not support payments", comment: "Error message during NWC setup")
                    }
                }
                else {
                    L.og.error("⚡️ NWC connection missing")
                }
            }
        }
    }
    
    func startNWC() {
        guard let nwc = try? NWCURI(string: nwcUri),
              let secret = nwc.secret,
              let relay = nwc.relay,
              let walletPubkey = nwc.walletPubkey
        else {
            nwcErrorMessage = String(localized:"Problem parsing NWC connection URI", comment:"Error message during NWC setup")
            return
        }
        
        bg().perform {
            guard let c = NWCConnection.createCustomConnection(context: bg(), secret: secret) else {
                L.og.error("Problem handling secret in NWCConnection.createCustomConnection")
                DispatchQueue.main.async {
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
                let newConnection = ConnectionPool.shared.addNWCConnection(connectionId:connectionId, url: relay)
                newConnection.connect()
                NWCRequestQueue.shared.nwcConnection = c
                Importer.shared.nwcConnection = c
                
                L.og.info("⚡️ Fetching 13194 (info) from NWC relay")
                ConnectionPool.shared.sendMessage(ClientMessage(onlyForNWCRelay: true, message: RM.getNWCInfo(walletPubkey: walletPubkey), relayType: .READ), afterPing: true)
            }
        }
        
        connectionTimeout?.invalidate()
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false, block: { _ in
            nwcErrorMessage = String(localized:"Could not fetch NWC info event from \(relay)", comment:"Error message during NWC setup")
        })
    }
    
    func removeExistingNWCsocket() {
        var removeKey:String?
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
