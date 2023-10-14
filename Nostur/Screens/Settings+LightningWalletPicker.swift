//
//  Settings+LightningWalletPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI

struct LightningWalletPicker: View {
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.defaultLightningWallet) {
            ForEach(SettingsStore.walletOptions) {
                Text($0.name).tag($0)
            }
        } label: {
            Text("Lightning wallet", comment:"Setting on settings screen")
        }
        .pickerStyle(.navigationLink)
    }
}

#Preview {
    NavigationStack {
        Form {
            LightningWalletPicker()
        }
    }
}
