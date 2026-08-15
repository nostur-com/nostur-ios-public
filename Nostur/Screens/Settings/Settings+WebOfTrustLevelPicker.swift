//
//  Settings+WebOfTrustLevelPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI

struct WebOfTrustLevelPicker: View {
    @ObservedObject private var wot = WebOfTrust.shared
    @ObservedObject private var settings: SettingsStore = .shared
    
    private var wotEnabled: Binding<Bool> {
        Binding(
            get: { settings.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue },
            set: { enabled in
                settings.webOfTrustLevel = enabled
                    ? SettingsStore.WebOfTrustLevel.on.rawValue
                    : SettingsStore.WebOfTrustLevel.off.rawValue
            }
        )
    }
    
    var body: some View {
        Toggle(isOn: wotEnabled) {
            Text("Web of Trust filter", comment: "Setting on settings screen")
        }
        .onChange(of: settings.webOfTrustLevel) { newValue in
            if newValue == SettingsStore.WebOfTrustLevel.on.rawValue {
                bg().perform {
                    guard let account = account() else { return }
                    let wotFollowingPubkeys = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys) // We don't include silent follows in WoT
                    wot.loadNormal(wotFollowingPubkeys: wotFollowingPubkeys, force: false)
                }
            }
            else if newValue == SettingsStore.WebOfTrustLevel.off.rawValue {
                Task { @MainActor in
                    await DMsVM.shared.load(force: true)
                }
            }
        }
    }
}

import NavigationBackport

#Preview {
    NRNavigationStack {
        Form {
            WebOfTrustLevelPicker()
        }
    }
}
