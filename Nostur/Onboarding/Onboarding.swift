//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct Onboarding: View {
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack {
            WelcomeSheet(offerTryOut: true)
                .interactiveDismissDisabled()
                .withNavigationDestinations()
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
