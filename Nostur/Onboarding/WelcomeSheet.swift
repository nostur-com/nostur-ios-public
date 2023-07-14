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
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack {
            Text("Welcome to **Nostur**", comment: "Welcoming the user to the app").font(.largeTitle)
            Text("See what's happening on nostr right now", comment: "Nostur intro text").font(.callout)
            
            VStack {
                NavigationLink {
                    NewAccountSheet()
                } label: {
                    Text("Create new account", comment: "Button to start creating a new account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    AddExistingAccountSheet(offerTryOut: true)
                } label: {
                    Text("Use existing account", comment: "Button to start using an existing account")
                        .frame(maxWidth: .infinity)
                }
                
                if (offerTryOut) {
                    NavigationLink {
                        TryGuestAccountSheet()
                    } label: {
                        Text("Try guest account", comment: "Button to try the guest account")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: 300)
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
    }
}

struct WelcomeSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            WelcomeSheet(offerTryOut: true)
        }
    }
}
