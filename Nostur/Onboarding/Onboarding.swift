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


