//
//  TryGuesTAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI

struct TryGuestAccountSheet: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    @EnvironmentObject var nav:NavigationModel
    @Environment(\.managedObjectContext) var viewContext
    @State var letsGo = false
    
    var body: some View {
        let _ = Self._printChanges()
        VStack(alignment: .center) {
            Text("Try Nostur as guest").font(.largeTitle)
            
            Text("The guest account is already following some people. You can read posts and view profiles, but you cannot post or like things until you create a new account yourself").multilineTextAlignment(.center)
                .padding()
            
            Button {
                letsGo = true
                ns.isOnboarding = false
//                nav.clear()
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

                    
            ns.pendingFirstContactsFetch = true
            let account = Account(context: viewContext)
            account.id = UUID()
            account.createdAt = Date()
            account.createdAt = Date()
            account.display_name = "Nostur Rookie"
            account.name = "NosturRookie"
            account.about = "Just trying things out"
            account.publicKey = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
            
            
            // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
            if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey!, context: viewContext) {
                for clEvent in clEvents {
                    viewContext.delete(clEvent)
                }
            }
            try! viewContext.save()
            
            
            // 1. Prefill from cached event (if in cache)
            Account.preFillReadOnlyAccountInfo(account: account, context: viewContext)
            Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
            
            do {
                try _ = ns.loadActiveAccount(account: account)
                let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: account.publicKey!))
                
                sp.sendMessage(message)
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
            
            
        }
        .onDisappear {
            // Did not continue with guest account, so undo the created account from .onAppear:
            if (!letsGo && ns.accounts.last != nil) {
                viewContext.delete(ns.accounts.last!)
                try! viewContext.save()
            }
            else if (letsGo) {
                try! viewContext.save()
                ns.isOnboarding = false
                nav.onboardingPath.removeLast(nav.onboardingPath.count)
            }
        }
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
