//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI
import NavigationBackport

struct Onboarding: View {
    @AppStorage("did_accept_terms") var didAcceptTerms = false
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    var body: some View {
//        let _ = Self._printChanges()
        if (!didAcceptTerms) {
            TermsAndConditions()
        }
        else {
            WelcomeSheet(offerTryOut: true)
                .interactiveDismissDisabled()
                .fullScreenCover(isPresented: $networkMonitor.isDisconnected, content: {
                    VStack(alignment: .center) {
                        Image(systemName: "wifi.exclamationmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                        Text("Internet connection unavailable")
                            .font(.title)
                        Text("Please try again when there is a connection")
                    }
                    .padding(10)
                })
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NBNavigationStack {
                Onboarding()
            }
        }
    }
}
