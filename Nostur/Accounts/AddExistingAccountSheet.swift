//
//  AddExistingAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI

struct AddExistingAccountSheet: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sp:SocketPool
    @State var key = ""
    @State var invalidKey = false
    
    var offerTryOut = false
    var accentColor: Color = Color.blue
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
            ZStack {
                VStack {
                    TextField("Public or private key (npub or nsec)", text: $key)
                        .padding()
                        .background(grayBackground)
                        .cornerRadius(5.0)
                        .padding(.bottom, 20)
                    
                    Text("Keys are stored on your device in iOS keychain").foregroundColor(.gray)
                        .font(.caption2)
                    
                    Button {
                        guard let nip19 = try? NIP19(displayString: key) else {
                            invalidKey = true
                            key = ""
                            return
                        }
                        if (key.prefix(5) == "npub1") {
                            addExistingReadOnlyAccount(pubkey: nip19.hexString)
                        }
                        if (key.prefix(5) == "nsec1") {
                            addExistingAccount(privkey: nip19.hexString)
                        }
                        if (!ns.onBoardingIsShown) {
                            dismiss()
                        }
                    } label: {
                        Text("Add")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: 300)
                    .buttonStyle(.borderedProminent)
                    
                    if (offerTryOut) {
                        NavigationLink {
                            TryGuestAccountSheet()
                        } label: {
                            Text("Skip and try as guest first")
                        }
                        .buttonStyle(.borderless)   
                        .padding(.top, 20)
                    }
                }
                VStack {
                    Spacer()
                    Text("Note: You can also add someone elses public key to try out Nostur from their perspective.").foregroundColor(.gray)
                }
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .padding()
            .alert("Invalid key", isPresented: $invalidKey) {
                Button("OK", role: .cancel) { }
            }
            .navigationTitle("Add existing account")
            .navigationBarTitleDisplayMode(.inline)
    }
    
    func addExistingAccount(privkey:String) {
        SavedEventsCache.shared.clear() // Because else we dont fetch new info... if we just fetched it before, maybe during onboarding
        let account = Account(context: viewContext)
        account.id = UUID()
        account.createdAt = Date()
        // TODO: Check if valid pubkey before save.
        // TODO: Check if account already exists..
        
        guard let keys = try? NKeys(privateKeyHex: privkey) else {
            invalidKey = true
            key = ""
            return
        }
        
        account.publicKey = keys.publicKeyHex()
        account.privateKey = keys.privateKeyHex()
        
        let ot = OnboardingTracker.shared
        ot.startOnboarding(pubkey: account.publicKey)
        
        
        // 1. Prefill from cached event
        Account.preFillReadOnlyAccountInfo(account: account, context: viewContext, forceOverwrite: true)
        Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
        
        // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for contactEvent in contactEvents {
                viewContext.delete(contactEvent)
            }
        }
        // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for clEvent in clEvents {
                viewContext.delete(clEvent)
            }
        }

        try! viewContext.save()
//        ns.objectWillChange.send()
        ns.setAccount(account: account)
        ns.onBoardingIsShown = false
        // 2. But also check if there are newer events
        if (!ot.didFetchKind0 || !ot.didFetchKind3) {
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: account.publicKey))
            SocketPool.shared.sendMessage(message)
        }
    }
    
    func addExistingReadOnlyAccount(pubkey:String) {
        SavedEventsCache.shared.clear() // Because else we dont fetch new info... if we just fetched it before, maybe during onboarding
        let ot = OnboardingTracker.shared
        ot.startOnboarding(pubkey: pubkey)
        let account = Account(context: viewContext)
        account.id = UUID()
        account.createdAt = Date()
        // TODO: Check if valid pubkey before save.
        // Convert npub to hex... etc
        account.publicKey = pubkey
        
        
        // 1. Prefill from cached event
        Account.preFillReadOnlyAccountInfo(account: account, context: viewContext, forceOverwrite: true)
        Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
        
        // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for contactEvent in contactEvents {
                viewContext.delete(contactEvent)
            }
        }
        // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for clEvent in clEvents {
                viewContext.delete(clEvent)
            }
        }
        
        try! viewContext.save()
        ns.objectWillChange.send()
        ns.setAccount(account: account)
        ns.onBoardingIsShown = false
        // 2. But also check if there are newer events
        if (!ot.didFetchKind0 || !ot.didFetchKind3) {
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: pubkey))
            SocketPool.shared.sendMessage(message)
            print("🟠🟠🟠 1")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: pubkey))
                SocketPool.shared.sendMessage(message)
                print("🟠🟠🟠 1")
            }
        }
    }
}

struct AddExistingAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddExistingAccountSheet()
            .withPreviewEnvironment()
    }
}
