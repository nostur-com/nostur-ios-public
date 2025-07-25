//
//  Settings+LightningWalletPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI
import NavigationBackport

struct LightningWalletPicker: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    @State private var lastCreatedNWCId: String? = nil
    @State private var lastNWCtype: String? = nil
    
    var body: some View {
        Picker(selection: $settings.defaultLightningWallet) {
            ForEach(SettingsStore.walletOptions) {
                Text($0.name).tag($0)
                    .foregroundColor(theme.primary)
            }
            
            if settings.activeNWCconnectionId == "", let lastCreatedNWCId {
                Text("Restore previous NWC configuration").tag(LightningWallet(name: "Restore previous NWC configuration", scheme: "nostur:nwc:last:\(lastCreatedNWCId)"))
                    .foregroundColor(theme.primary)
                    .onTapGesture {
                        settings.activeNWCconnectionId = lastCreatedNWCId
                        if let lastNWCtype, lastNWCtype == "ALBY" {
                            settings.defaultLightningWallet = LightningWallet(name: "Alby (Nostr Wallet Connect)", scheme: "nostur:nwc:alby:")
                        }
                        else {
                            settings.defaultLightningWallet = LightningWallet(name: "Custom Nostr Wallet Connect...", scheme: "nostur:nwc:custom:")
                        }
                    }
            }
        } label: {
            Text("Lightning wallet", comment:"Setting on settings screen")
        }
        .pickerStyleCompatNavigationLink()
        .onAppear {
            fetchLastNWCConnection()
        }
    }
    
    func fetchLastNWCConnection() {
        guard let nwc = NWCConnection.fetchConnection(context: DataProvider.shared().viewContext) else { return }
        lastNWCtype = nwc.type
        lastCreatedNWCId = nwc.connectionId
    }
}

import NavigationBackport

#Preview {
    NBNavigationStack {
        Form {
            LightningWalletPicker()
        }
    }
}
