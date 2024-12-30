//
//  AlbyNWCConnectSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import SwiftUI

struct AlbyNWCConnectSheet: View {
    @EnvironmentObject private var themes:Themes
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    @State var nwcConnection:NWCConnection? = nil
    @State var nwcConnectSuccess = false
    @State var showDisconnect = false
    @State var nwcErrorMessage = ""
    @State var lud16:String? = nil
    @ObservedObject var ss:SettingsStore = .shared
    
    var body: some View {
        VStack {
            Image("AlbyLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 50)
            if (nwcConnectSuccess) {
                Text("Your **Alby** wallet is now connected with **Nostur**, you can now enjoy a seamless zapping experience!")
                    .multilineTextAlignment(.center)
                    .padding(10)
                if let lud16 = lud16 {
                    Text("Your address for receiving zaps has been set to: \(lud16)")
                }
            }
            else {
                Text("Connect your **Alby** wallet with **Nostur** for a seamless zapping experience")
                    .multilineTextAlignment(.center)
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
                        let ctx = bg()
                        ctx.perform {
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
                                NWCConnection.delete(ss.activeNWCconnectionId, context: ctx)
                            }
                            DispatchQueue.main.async {
                                ss.activeNWCconnectionId = ""
                            }
                            showDisconnect = false
                            nwcConnectSuccess = false
                        }
                    }
                }
            }
            else {
                Button(String(localized:"Connect Alby wallet", comment:"Button to connect to Alby wallet")) { startNWC() }
                    .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
            }
            
            if !nwcErrorMessage.isEmpty {
                Text(nwcErrorMessage).fontWeight(.bold).foregroundColor(.red)
            }
            
            
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle((String(localized:"Nostr Wallet Connect", comment:"Navigation title for setting up Nostr Wallet Connect (NWC)")))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if nwcConnectSuccess {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            
            ToolbarItem(placement: .cancellationAction) {
                if !nwcConnectSuccess {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Determine if we show "Connection success" or disconnect button
            if !ss.activeNWCconnectionId.isEmpty {
                nwcConnectSuccess = true
                showDisconnect = true // Only show after opening again, because showing right after connecting is confusing
            }
        }
        .onReceive(receiveNotification(.nwcCallbackReceived)) { notification in
            guard let account = account() else { return }
            
            // When we redirect back from Alby to app:
            let albyCallback = notification.object as! AlbyCallback
            
            guard let queryItems = URLComponents(url: albyCallback.url, resolvingAgainstBaseURL: false)?.queryItems else {
                L.og.error("Could not connect Alby wallet, problem parsing queryItems");
                nwcErrorMessage = "Could not connect Alby wallet"
                return
            }
            guard let nwcRelay = queryItems.first(where: { $0.name == "relay" })?.value else {
                L.og.error("Could not connect Alby wallet, relay missing in queryItems");
                nwcErrorMessage = "Could not connect Alby wallet"
                return
            }
            guard let nwcPubkey = queryItems.first(where: { $0.name == "pubkey" })?.value else {
                L.og.error("Could not connect Alby wallet, pubkey missing in queryItems");
                nwcErrorMessage = "Could not connect Alby wallet"
                return
            }
            
            guard let nwcConnection = nwcConnection else {
                L.og.error("Could not connect Alby wallet, nwcConnction = nil");
                nwcErrorMessage = "Could not connect Alby wallet"
                return
            }
            bg().perform {
                nwcConnection.walletPubkey = nwcPubkey
                nwcConnection.relay = nwcRelay
                nwcConnection.methods = "pay_invoice"
                let connectionId = nwcConnection.connectionId
                let relay = nwcConnection.relay
                
                L.og.info("⚡️ Adding NWC connection")
                
                ConnectionPool.shared.addNWCConnection(connectionId: connectionId, url: relay) { conn in
                    if !conn.isConnected {
                        conn.connect()
                    }
                }
                
                NWCRequestQueue.shared.nwcConnection = nwcConnection
                Importer.shared.nwcConnection = nwcConnection
                
                DispatchQueue.main.async {
                    ss.activeNWCconnectionId = connectionId
                    nwcConnectSuccess = true
                }
                bgSave()
            }
            
            if account.lud06.isEmpty && account.lud16.isEmpty {
                if let lud16 = queryItems.first(where: { $0.name == "lud16" })?.value {
                    account.lud16 = lud16
                    do {
                        try publishMetadataEvent(account)
                        self.lud16 = lud16
                        updateZapperPubkey(account)
                    }
                    catch {
                        L.og.error("Error publishing new account kind 0")
                    }
                }
            }
        }
    }
    
    func updateZapperPubkey(_ account: CloudAccount) {
        guard account.lud16 != "" else { return }
        guard let contact = Contact.fetchByPubkey(account.publicKey, context: DataProvider.shared().viewContext) else { return }
        guard let contactLud16 = contact.lud16, contactLud16 != account.lud16 else { return }
        
        Task {
            let response = try await LUD16.getCallbackUrl(lud16: account.lud16)
            if let zapperPubkey = response.nostrPubkey, (response.allowsNostr ?? false) {
                DispatchQueue.main.async {
                    contact.zapperPubkey = zapperPubkey
                }
                L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
            }
        }
    }
    
    func startNWC() {
        bg().perform {
            nwcConnection = try? NWCConnection.createAlbyConnection(context: bg())
            
            if let nwcConnection = nwcConnection, let nwcUrl = URL(string:"https://nwc.getalby.com/apps/new?c=Nostur&pubkey=\(nwcConnection.pubkey)&return_to=nostur%3A%2F%2Fnwc_callback") {
                DispatchQueue.main.async {
                    openURL(nwcUrl)
                }
            }
        }
        
        
        //        if let nwcUrl = URL(string:"https://nwc.getalby.com/apps/new?c=Nostur") { // This one returns with 'nostrwalletconnect' scheme so not usable.
        //            openURL(nwcUrl)
        //        }
    }
}

import NavigationBackport

struct AlbyNWCConnectSheet_Previews: PreviewProvider {
    static var previews: some View {
        NBNavigationStack {
            AlbyNWCConnectSheet()
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}

struct AlbyCallback: Identifiable {
    let id = UUID()
    let url:URL
}
