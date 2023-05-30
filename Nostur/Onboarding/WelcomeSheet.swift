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
        let _ = Self._printChanges()
        VStack {
            Text("Welcome to **Nostur**").font(.largeTitle)
            Text("See what's happening on nostr right now").font(.callout)
            
            VStack {
                NavigationLink {
                    NewAccountSheet()
                } label: {
                    Text("Create new account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    AddExistingAccountSheet(offerTryOut: true)
                } label: {
                    Text("Use existing account")
                        .frame(maxWidth: .infinity)
                }
                
                if (offerTryOut) {
                    NavigationLink {
                        TryGuestAccountSheet()
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
    }
}

struct WelcomeSheet_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeSheet(offerTryOut: true)
            .withPreviewEnvironment()
    }
}
