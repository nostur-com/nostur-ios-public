//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct Onboarding: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    
    var body: some View {
        let _ = Self._printChanges()
        if (ns.isOnboarding) || (ns.account == nil) {
            Color.clear
                .fullScreenCover(isPresented: $ns.isOnboarding) {
                    NavigationStack(path: $nav.onboardingPath) {
                        WelcomeSheet(offerTryOut: true)
                            .withNavigationDestinations()
                    }
                }
        }
        else if (ns.account != nil) {
            NosturRootMenu()
                .sheet(isPresented: $ns.readOnlyAccountSheetShown) {
                    ReadOnlyAccountInformationSheet()
                        .presentationDetents([ .large])
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
