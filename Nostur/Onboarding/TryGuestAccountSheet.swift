//
//  TryGuestAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct TryGuestAccountSheet: View {
    @EnvironmentObject var theme:Theme
    @EnvironmentObject var ns:NosturState
    let sp:SocketPool = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @State var letsGo = false
    @State var didCreate = false
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(alignment: .center) {
            Text("Try Nostur as guest", comment:"Heading for message")
                .multilineTextAlignment(.center)
                .font(.largeTitle)
            
            Text("The guest account is already following some people. You can read posts and view profiles, but you cannot post or like things until you create a new account yourself", comment: "Message during onboarding about the Guest Account").multilineTextAlignment(.center)
                .padding()
            
            Button {
                tryGuestAccount()
            } label: {
                Text("Let's go!", comment: "Button to start using Nostur, during onboarding")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
        }
        .frame(maxWidth: 300)
        .onAppear {
            // Start onboarding already.. speed up..
            let countBefore = ns.accounts.count
            if !ns.accounts.contains(where: { $0.publicKey == NosturState.GUEST_ACCOUNT_PUBKEY }) {
                let guestAccount = GuestAccountManager.shared.createGuestAccount()
                ns.setAccount(account: guestAccount)
                if ns.accounts.count > countBefore {
                    didCreate = true
                }
            }
            do {
                try NewOnboardingTracker.shared.start(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY)
                L.onboarding.info("✈️✈️✈️ ONBORADING SPEED UP, FETCHING 0 + 3")
    //                    req(RM.getUserMetadataAndContactList(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY))
            }
            catch {
                L.onboarding.error("🔴🔴✈️✈️✈️ ONBORADING ERROR \(error)")
            }
        }
        .onDisappear {
            // back without trying out guest, so should cancel onboarding and creating guest
            let guestAccount = try? Account.fetchAccount(publicKey: NosturState.GUEST_ACCOUNT_PUBKEY, context: viewContext)
            
            if let guestAccount, !letsGo && didCreate {
                viewContext.delete(guestAccount)
                NewOnboardingTracker.shared.abort()
            }
            else {
                ns.setAccount(account: guestAccount)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func tryGuestAccount() {
        letsGo = true
        ns.onBoardingIsShown = false
        dismiss()
    }
}

struct TryGuestAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            TryGuestAccountSheet()
        }
    }
}
