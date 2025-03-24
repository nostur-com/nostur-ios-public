//
//  WelcomeSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI
import NavigationBackport

struct WelcomeSheet: View {
    @EnvironmentObject private var themes: Themes
    public var offerTryOut = false
    
    var body: some View {
        VStack {
            Text("Welcome to **Nostur**", comment: "Welcoming the user to the app").font(.largeTitle)
            Text("See what's happening on nostr right now", comment: "Nostur intro text").font(.callout)
                .padding(.bottom, 20)
            
            VStack {
                Group {
                    NavigationLink {
                        NewAccountSheet()
                    } label: {
                        Text("Create new account", comment: "Button to start creating a new account")
                            .frame(maxWidth: .infinity)
                    }
                    .fontWeightBold()
                    .tint(.black.opacity(0.65))

                    NavigationLink {
                        AddExistingAccountSheet(offerTryOut: true)
                    } label: {
                        Text("Use existing account", comment: "Button to start using an existing account")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.black.opacity(0.1))
                    
                    if (offerTryOut) {
                        NavigationLink {
                            TryGuestAccountSheet()
                        } label: {
                            Text("Try guest account", comment: "Button to try the guest account")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.black.opacity(0.1))
                    }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                
                
                VStack {
                    Text("By continuing you agree to the")
                        .padding(.top, 30)
                    NavigationLink {
                        TermsAndConditions()
                    } label: {
                        Text("Terms and Conditions")
                            .foregroundColor(.white)
                            .underline()
                    }
                }
                .opacity(0.6)
            }
            .frame(maxWidth: 300)
            
        }
        .wowBackground()
        .foregroundColor(Color.white)
    }
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            WelcomeSheet(offerTryOut: true)
        }
    }
}
