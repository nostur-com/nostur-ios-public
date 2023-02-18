//
//  WelcomeSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct WelcomeSheet: View {
    
    var offerTryOut = false
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            Text("Welcome to **Nostur**").font(.largeTitle)
            Text("See what's happening on nostr right now").font(.callout)
            
            VStack {
                Button {
                    nav.onboardingPath.append(ViewPath.CreateNewAccount)
                } label: {
                    Text("Create new account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    nav.onboardingPath.append(ViewPath.UseExistingAccount)
                } label: {
                    Text("Use existing account")
                        .frame(maxWidth: .infinity)
                }
                
                if (offerTryOut) {
                    Button {
                        nav.onboardingPath.append(ViewPath.TryGuestAccount)
                    } label: {
                        Text("Try guest account")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: 300)
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
        .onAppear {
            ns.isOnboarding = true
        }
    }
}

struct WelcomeSheet_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            WelcomeSheet()
        }
        .withPreviewEnvironment()
    }
}
