//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct Onboarding: View {
    @AppStorage("did_accept_terms") var didAcceptTerms = false
    
    var body: some View {
//        let _ = Self._printChanges()
        if (!didAcceptTerms) {
            TermsAndConditions()
        }
        else {
            NavigationStack {
                WelcomeSheet(offerTryOut: true)
                    .interactiveDismissDisabled()
                    .withNavigationDestinations()
            }
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            Onboarding()
        }
    }
}
