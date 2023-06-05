import SwiftUI

struct AlbyNWCConnectSheet: View {
    @State var awaitingConnectionId = ""
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    @State var nwcConnectSuccess = false
    @State var showDisconnect = false
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
                        let ctx = DataProvider.shared().bg
                        ctx.perform {
                            var removeKey:String?
                            SocketPool.shared.sockets.values.forEach { managedClient in
                                if managedClient.isNWC {
                                    managedClient.disconnect()
                                    removeKey = managedClient.relayId
                                }
                            }
                            if let removeKey {
                                DispatchQueue.main.async {
                                    SocketPool.shared.removeSocket(removeKey)
                                }
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
                Button("Connect Alby wallet") { startNWC() }
                    .buttonStyle(.borderedProminent)
            }
            
            
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle((String(localized:"Nostr Wallet Connect", comment:"Navigation title for setting up Nostr Wallet Connect (NWC)")))
        .toolbar {
            if nwcConnectSuccess {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            else {
                ToolbarItem(placement: .cancellationAction) {
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
        .onReceive(receiveNotification(.nwcCallbackReceived)) { _ in
            // When we redirect back from Alby to app:
            nwcConnectSuccess = true
            ss.activeNWCconnectionId = awaitingConnectionId
            
            DataProvider.shared().bg.perform {
                if let nwcConnection = NWCConnection.fetchConnection(ss.activeNWCconnectionId, context: DataProvider.shared().bg) {
                    _ = SocketPool.shared.addNWCSocket(connectionId:nwcConnection.connectionId, url: nwcConnection.relay)
                    NWCRequestQueue.shared.nwcConnection = nwcConnection
                    Importer.shared.nwcConnection = nwcConnection
                }
            }
        }
    }
    
    func startNWC() {
        let c = NWCConnection.createAlbyConnection(context: DataProvider.shared().viewContext)
        awaitingConnectionId = c.connectionId
        
        // Hardcoded details for now because 'nostrwalletconnect' scheme callback is hijacked by whichever app is installed last
        c.walletPubkey = "69effe7b49a6dd5cf525bd0905917a5005ffe480b58eeb8e861418cf3ae760d9"
        c.relay = "wss://relay.getalby.com/v1"
        c.methods = "pay_invoice"
        
        if let nwcUrl = URL(string:"https://nwc.getalby.com/apps/new?c=Nostur&pubkey=\(c.pubkey)&return_to=nostur%3A%2F%2Fnwc_callback") {
            openURL(nwcUrl)
        }
        
        //        if let nwcUrl = URL(string:"https://nwc.getalby.com/apps/new?c=Nostur") { // This one returns with 'nostrwalletconnect' scheme so not usable.
        //            openURL(nwcUrl)
        //        }
    }
}

struct AlbyNWCConnectSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AlbyNWCConnectSheet()
        }
        .previewDevice("iPhone 14")
    }
}
