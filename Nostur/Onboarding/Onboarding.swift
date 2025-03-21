//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI
import NavigationBackport

struct Onboarding: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    var body: some View {
        NBNavigationStack {
            WelcomeSheet(offerTryOut: true)
                .foregroundColor(.white)
                .interactiveDismissDisabled()
                .wowBackground()
                .fullScreenCover(isPresented: $networkMonitor.isDisconnected) {
                    NoInternetView()
                }
                
        }
    }
}

#Preview {
    PreviewContainer {
        Onboarding()
    }
}


