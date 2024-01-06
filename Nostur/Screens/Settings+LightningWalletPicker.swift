//
//  Settings+LightningWalletPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI
import NavigationBackport

struct LightningWalletPicker: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.defaultLightningWallet) {
            ForEach(SettingsStore.walletOptions) {
                Text($0.name).tag($0)
                    .foregroundColor(themes.theme.primary)
            }
        } label: {
            Text("Lightning wallet", comment:"Setting on settings screen")
        }
        .pickerStyle(.navigationLink)
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
