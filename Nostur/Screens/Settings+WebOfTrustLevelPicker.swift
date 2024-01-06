//
//  Settings+WebOfTrustLevelPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/10/2023.
//

import SwiftUI

struct WebOfTrustLevelPicker: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var wot = WebOfTrust.shared
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        Picker(selection: $settings.webOfTrustLevel) {
            ForEach(SettingsStore.WebOfTrustLevel.allCases, id:\.self) {
                Text($0.localized).tag($0.rawValue)
                    .foregroundColor(themes.theme.primary)
            }
        } label: {
            Text("Web of Trust filter", comment:"Setting on settings screen")
        }
        .pickerStyle(.navigationLink)
        .onChange(of: settings.webOfTrustLevel) { newValue in
            if newValue == SettingsStore.WebOfTrustLevel.normal.rawValue {
                bg().perform {
                    guard let account = account() else { return }
                    let wotFollowingPubkeys = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys) // We don't include silent follows in WoT
                    wot.loadNormal(wotFollowingPubkeys: wotFollowingPubkeys, force: false)
                }
            }
            else if newValue == SettingsStore.WebOfTrustLevel.off.rawValue {
                DirectMessageViewModel.default.load()
            }
            else {
                wot.updateViewData()
            }
        }
    }
}

import NavigationBackport

#Preview {
    NBNavigationStack {
        Form {
            WebOfTrustLevelPicker()
        }
    }
}
