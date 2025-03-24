//
//  TryGuestAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct TryGuestAccountSheet: View {
    @EnvironmentObject private var themes:Themes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @State var letsGo = false
    @State var didCreate = false
    
    var body: some View {
        VStack(alignment: .center) {
            if letsGo {
                ProgressView()
            }
            else {
                Text("Try Nostur as guest", comment:"Heading for message")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle)
                
                Text("The guest account is already following some people. You can read posts and view profiles, but you cannot post or react to anything until you create a new account yourself", comment: "Message during onboarding about the Guest Account").multilineTextAlignment(.center)
                    .padding()
                
                Button {
                    tryGuestAccount()
                } label: {
                    Text("Let's go!", comment: "Button to start using Nostur, during onboarding")
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .fontWeightBold()
                .tint(.black.opacity(0.65))
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: 300)
        .onAppear {
            // Start onboarding already.. speed up..
            let countBefore = AccountsState.shared.accounts.count
            if !AccountsState.shared.accounts.contains(where: { $0.publicKey == GUEST_ACCOUNT_PUBKEY }) {
                let guestAccount = GuestAccountManager.shared.createGuestAccount()
                AccountsState.shared.changeAccount(guestAccount)
                if AccountsState.shared.accounts.count > countBefore {
                    didCreate = true
                }
            }
            do {
                try NewOnboardingTracker.shared.start(pubkey: GUEST_ACCOUNT_PUBKEY)
                L.onboarding.info("✈️✈️✈️ ONBOARDING SPEED UP, FETCHING 0 + 3")
            }
            catch {
                L.onboarding.error("🔴🔴✈️✈️✈️ ONBOARDING ERROR \(error)")
            }
        }
        .onDisappear {
            // back without trying out guest, so should cancel onboarding and creating guest
            let guestAccount = try? CloudAccount.fetchAccount(publicKey: GUEST_ACCOUNT_PUBKEY, context: viewContext)
            
            if let guestAccount, !letsGo && didCreate {
                viewContext.delete(guestAccount)
                NewOnboardingTracker.shared.abort()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(letsGo)
        .wowBackground()
        .foregroundColor(Color.white)
    }
    
    func tryGuestAccount() {
        letsGo = true
        let guestAccount = try? CloudAccount.fetchAccount(publicKey: GUEST_ACCOUNT_PUBKEY, context: viewContext)
        
        if let guestAccount {
            AccountsState.shared.changeAccount(guestAccount)
        }
        AccountsState.shared.loadAccountsState()
    }
}

struct TryGuestAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            TryGuestAccountSheet()
        }
    }
}
