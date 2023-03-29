//
//  Onboarding.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct Onboarding: View {
    
    @EnvironmentObject var ns:NosturState
    @State var path = NavigationPath()
    
    var body: some View {
        let _ = Self._printChanges()
        if (ns.onBoardingIsShown) {
            Color.clear
                .fullScreenCover(isPresented: $ns.onBoardingIsShown) {
                    NavigationStack() {
                        WelcomeSheet(offerTryOut: true)
                            .interactiveDismissDisabled()
                            .withNavigationDestinations()
                    }
                }
                .onReceive(receiveNotification(.endOnboarding)) { _ in
                    ns.onBoardingIsShown = false
                }
        }
        else if (ns.account != nil) {
            NosturRootMenu()
//                .ignoresSafeArea()
                .sheet(isPresented: $ns.readOnlyAccountSheetShown) {
                    ReadOnlyAccountInformationSheet()
                        .presentationDetents([ .large])
                        .environmentObject(ns)
                }
        }
        else {
            Text("do... onBoardingIsShown = true")
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
