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
                letsGo = true
                ns.onBoardingIsShown = false
            } label: {
                Text("Let's go!")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 300)
        .onAppear {
            if let account = try? Account.fetchAccount(publicKey: NosturState.GUEST_ACCOUNT_PUBKEY, context: viewContext) {
                ns.setAccount(account: account)
            }
        }
        .onDisappear {
            if (letsGo) {
                ns.onBoardingIsShown = false
                dismiss()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
