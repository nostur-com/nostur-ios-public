//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct Onboarding: View {
    @EnvironmentObject var ns:NosturState
    @AppStorage("did_accept_terms") var didAcceptTerms = true // TODO: DONT FORGET TO SET TO FALSE ON APP STORE SUBMIT
    
    var body: some View {
        let _ = Self._printChanges()
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
        VStack {
            Onboarding()
        }
        .withPreviewEnvironment()
    }
}
