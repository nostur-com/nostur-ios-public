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
            // prepare guest account in background

//            let ar = Account.fetchRequest()
//            ar.entity = Account.entity()
//            ar.predicate = NSPredicate(format: "publicKey == %@", NosturState.GUEST_ACCOUNT_PUBKEY)
            
            var account:Account? = nil
            account = try? Account.fetchAccount(publicKey: NosturState.GUEST_ACCOUNT_PUBKEY, context: viewContext)
            
            if (account == nil) {
                account = Account(context: viewContext)
                account!.id = UUID()
                account!.createdAt = Date()
                account!.createdAt = Date()
                account!.display_name = "Nostur Rookie"
                account!.name = "NosturRookie"
                account!.about = "Just trying things out"
                account!.publicKey = NosturState.GUEST_ACCOUNT_PUBKEY
                didCreate = true
            }
            
            Importer.shared.existingIds.removeAll() // Because else we dont fetch new info... if we just fetched it before, maybe during onboarding
            Account.preFillReadOnlyAccountInfo(account: account!, context: viewContext, forceOverwrite: true)
            Account.preFillReadOnlyAccountFollowing(account: account!, context: viewContext)
            ns.setAccount(account: account!)
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: account!.publicKey))
            sp.sendMessage(message)
        }
        .onDisappear {
            // Did not continue with guest account, so undo the created account from .onAppear:
            if (!letsGo && didCreate && ns.accounts.last != nil) {
                viewContext.delete(ns.accounts.last!)
                try! viewContext.save()
            }
            else if (letsGo) {
                try! viewContext.save()
                ns.onBoardingIsShown = false
                dismiss()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TryGuesTAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TryGuestAccountSheet()
        }
        .withPreviewEnvironment()
    }
}
