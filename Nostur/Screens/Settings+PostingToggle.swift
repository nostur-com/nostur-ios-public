//
//  Settings+Posting.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/12/2023.
//

import SwiftUI

struct PostingToggle: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings: SettingsStore = .shared
    
    private var accounts:[CloudAccount] {
        NRState.shared.accounts
            .sorted(by: { $0.publicKey < $1.publicKey })
            .filter { $0.privateKey != nil }
    }

    private func toggleAccount(_ account:CloudAccount) {
        if settings.excludedUserAgentPubkeys.contains(account.publicKey) {
            settings.excludedUserAgentPubkeys.remove(account.publicKey)
        }
        else {
            settings.excludedUserAgentPubkeys.insert(account.publicKey)
        }
    }
    
    private func isExcluded(_ account:CloudAccount) -> Bool {
        return  settings.excludedUserAgentPubkeys.contains(account.publicKey)
    }
    
    var body: some View {
        Toggle(isOn: $settings.postUserAgentEnabled) {
            Text("Include Nostur in post metadata", comment:"Setting on settings screen")
            Text("Lets others know you are posting from Nostur", comment:"Setting on settings screen")
            if settings.postUserAgentEnabled {
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
}

#Preview {
    PreviewContainer({ pe in pe.loadAccounts() }) {
        NavigationStack {
            Form {
                Section("Posting") {
                    PostingToggle()
                }
            }
        }
    }
}
