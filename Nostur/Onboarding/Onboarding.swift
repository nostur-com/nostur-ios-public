//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI
import NavigationBackport

struct Onboarding: View {
    @ObservedObject private var networkMonitor: NetworkMonitor = .shared
    
    var body: some View {
        NBNavigationStack {
            WelcomeSheet(offerTryOut: true)
                .foregroundColor(.white)
                .interactiveDismissDisabled()
                .wowBackground()
                .foregroundColor(Color.white)
                .fullScreenCover(isPresented: $networkMonitor.isDisconnected) {
                    NoInternetView()
                }
                .onAppear {
                    // Workaround for where account sync is messed up
                    // Fall back to next last used account
                    if let nextAccount = AccountsState.shared.accounts.sorted(by: { $0.lastLoginAt > $1.lastLoginAt }).first(where: { $0.publicKey != GUEST_ACCOUNT_PUBKEY }) {
                        AccountsState.shared.changeAccount(nextAccount)
                    }
                }
        }
        
        // Sets toolbar (Back button) color
        .tint(Themes.default.theme.accent)
        .accentColor(Themes.default.theme.accent)
    }
}

#Preview {
    PreviewContainer {
        Onboarding()
    }
}


