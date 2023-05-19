//
//  TryGuesTAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct TryGuestAccountSheet: View {
    
    @EnvironmentObject var ns:NosturState
    let sp:SocketPool = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @State var letsGo = false
    @State var didCreate = false
    
    var body: some View {
        let _ = Self._printChanges()
        VStack(alignment: .center) {
            Text("Try Nostur as guest").font(.largeTitle)
            
            Text("The guest account is already following some people. You can read posts and view profiles, but you cannot post or like things until you create a new account yourself").multilineTextAlignment(.center)
                .padding()
            
            Button {
                tryGuestAccount()
            } label: {
                Text("Let's go!")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
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
    //                    print("✈️✈️✈️ ONBORADING SPEED UP, FETCHING 0 + 3")
    //                    req(RM.getUserMetadataAndContactList(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY))
            }
            catch {
                print("🔴🔴✈️✈️✈️ ONBORADING ERROR 123")
            }
        }
        .onDisappear {
            // back without trying out guest, so should cancel onboarding and creating guest
            let guestAccount = try? Account.fetchAccount(publicKey: NosturState.GUEST_ACCOUNT_PUBKEY, context: viewContext)
            
            if let guestAccount, !letsGo && didCreate {
                viewContext.delete(guestAccount)
                Importer.shared.existingIds = []
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
        VStack {
            TryGuestAccountSheet()
        }
        .withPreviewEnvironment()
    }
}
