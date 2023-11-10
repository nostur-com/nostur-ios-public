//
//  AddExistingAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI

struct AddExistingAccountSheet: View {
    
    init(offerTryOut: Bool = false) {
        self.offerTryOut = offerTryOut
    }
    
    public var offerTryOut = false
    
    @EnvironmentObject private var themes:Themes
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var invalidKey = false
    
    
    private var grayBackground: Color = Color.gray.opacity(0.2)
    private var isNsecbunkerKey:Bool { key.prefix(5) == "npub1" && (key.contains("#")) && key.split(separator: "#").count == 2 && key.split(separator: "#")[1].count == 64 }
    
    @ObservedObject private var bunkerManager = NSecBunkerManager.shared
    
    var body: some View {
            ZStack {
                VStack {
                    TextField(String(localized:"Public or private key (npub or nsec)", comment:"Input field to enter public or private key on Add Existing Account screen"), text: $key)
                        .padding()
                        .background(grayBackground)
                        .cornerRadius(5.0)
                        .padding(.bottom, 20)
                    
//                    Text("Keys are stored on your device in iOS keychain", comment:"Informational message about key storage on Add Existing Account screen").foregroundColor(.gray)
//                        .font(.caption2)
                    
                    Button {
                        if isNsecbunkerKey {
                            let bunkerNpub = String(key.split(separator: "#")[0])
                            let token = String(key.split(separator: "#")[1])
                            guard let nip19 = try? NIP19(displayString: bunkerNpub) else {
                                invalidKey = true
                                key = ""
                                return
                            }
                            addExistingBunkerAccount(pubkey: nip19.hexString, token: token)
                        }
                        else {
                            guard let nip19 = try? NIP19(displayString: key) else {
                                invalidKey = true
                                key = ""
                                return
                            }
                            
                            if (key.prefix(5) == "npub1") {
                                addExistingReadOnlyAccount(pubkey: nip19.hexString)
                            }
                            else if (key.prefix(5) == "nsec1") {
                                addExistingAccount(privkey: nip19.hexString)
                            }
                            if (!NRState.shared.onBoardingIsShown) {
                                dismiss()
                            }
                        }
                        
                    } label: {
                        if bunkerManager.state == .connecting {
                            ProgressView()
                                .padding(.vertical, 10)
                        }
                        else if (isNsecbunkerKey) {
                            Text("Add (nsecBunker)")
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }
                        else {
                            Text("Add")
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: 300)
                    .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                    .disabled(bunkerManager.state == .connecting || (bunkerManager.isSelfHostedNsecBunker && bunkerManager.invalidSelfHostedAddress))
                    
                    if isNsecbunkerKey {
                        
                        Toggle(isOn: $bunkerManager.isSelfHostedNsecBunker) {
                            Text("Self-hosted nsecBunker")
                        }.padding()
                        if bunkerManager.isSelfHostedNsecBunker {
                            TextField(text: $bunkerManager.ncRelay) {
                                Text("Enter nsecBunker relay address")
                            }
                            .keyboardType(.URL)
                            .padding()
                            .background(grayBackground)
                            .cornerRadius(5.0)
                            .padding(.bottom, 10)
                        }
                    }
                    
                    if (offerTryOut) {
                        NavigationLink {
                            TryGuestAccountSheet()
                        } label: {
                            Text("Skip and try as guest first", comment: "Button to skip adding account and use the guest account instead")
                        }
                        .buttonStyle(.borderless)   
                        .padding(.top, 20)
                    }
                    if !bunkerManager.error.isEmpty {
                        Text(bunkerManager.error).foregroundColor(Color.red)
                    }
                }
                VStack {
                    Spacer()
                        Text("Note: You can also add someone elses public key to try out Nostur from their perspective.", comment: "Informational message on Add Existing Account screen").foregroundColor(.gray)
                }
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .padding()
            .alert(String(localized:"Invalid key", comment: "Message shown when user has entered an invalid key"), isPresented: $invalidKey) {
                Button("OK", role: .cancel) { }
            }
                        .navigationTitle(String(localized:"Add existing account", comment: "Navigation title for Add Existing Account screen"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: bunkerManager.state) { bunkerState in
                if bunkerState == .connected {
                    guard let account = bunkerManager.account else { return }
                    if bunkerManager.isSelfHostedNsecBunker {
                        account.ncRelay = bunkerManager.ncRelay
                    }
                    // Continue onboarding..
                    
                    // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
                    if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
                        for contactEvent in contactEvents {
                            let eventId = contactEvent.id
                            bg().perform {
                                Importer.shared.existingIds.removeValue(forKey: eventId)
                            }
                            viewContext.delete(contactEvent)
                        }
                    }
                    // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
                    if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
                        for clEvent in clEvents {
                            let eventId = clEvent.id
                            bg().perform {
                                Importer.shared.existingIds.removeValue(forKey: eventId)
                            }
                            viewContext.delete(clEvent)
                        }
                    }
                    
                    try! viewContext.save()
                    NRState.shared.changeAccount(account)
                    NRState.shared.onBoardingIsShown = false
                    dismiss()
                    
                    do {
                        try NewOnboardingTracker.shared.start(pubkey: account.publicKey)
                    }
                    catch {
                        L.og.error("🔴🔴 Failed to start onboarding")
                    }
                }
                else if bunkerState == .error {
                    if let account = bunkerManager.account {
                        NIP46SecretManager.shared.deleteSecret(account: account)
                        viewContext.delete(account)
//                        NRState.shared.loadAccounts()
                    }
                }
            }
    }
    
    private func addExistingAccount(privkey:String) {
        guard let keys = try? NKeys(privateKeyHex: privkey) else {
            invalidKey = true
            key = ""
            return
        }
        
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: keys.publicKeyHex(), context: viewContext)) {
            existingAccount.privateKey = keys.privateKeyHex()
            existingAccount.isNC = false
            NRState.shared.changeAccount(existingAccount)
            NRState.shared.onBoardingIsShown = false
            return
        }
        
        let account = CloudAccount(context: viewContext)
        account.createdAt = Date()        
        account.publicKey = keys.publicKeyHex()
        account.privateKey = keys.privateKeyHex()
        
        // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for contactEvent in contactEvents {
                let eventId = contactEvent.id
                bg().perform {
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                }
                viewContext.delete(contactEvent)
            }
        }
        
        // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for clEvent in clEvents {
                let eventId = clEvent.id
                bg().perform {
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                }
                viewContext.delete(clEvent)
            }
        }

        try! viewContext.save()
//        NRState.shared.loadAccounts()
        NRState.shared.changeAccount(account)
        NRState.shared.onBoardingIsShown = false
        
        do {
            try NewOnboardingTracker.shared.start(pubkey: account.publicKey)
        }
        catch {
            L.og.error("🔴🔴 Failed to start onboarding")
        }
    }
    
    private func addExistingReadOnlyAccount(pubkey:String) {
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: pubkey, context: viewContext)) {
            NRState.shared.changeAccount(existingAccount)
            NRState.shared.onBoardingIsShown = false
            return
        }

        let account = CloudAccount(context: viewContext)
        account.createdAt = Date()
        account.publicKey = pubkey
        
        // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for contactEvent in contactEvents {
                let eventId = contactEvent.id
                bg().perform {
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                }
                viewContext.delete(contactEvent)
            }
        }
        // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: viewContext) {
            for clEvent in clEvents {
                let eventId = clEvent.id
                bg().perform {
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                }
                viewContext.delete(clEvent)
            }
        }
        
        try! viewContext.save()
//        NRState.shared.loadAccounts()
        NRState.shared.changeAccount(account)
        NRState.shared.onBoardingIsShown = false
        
        do {
            try NewOnboardingTracker.shared.start(pubkey: account.publicKey)
        }
        catch {
            L.og.error("🔴🔴 Failed to start onboarding")
        }
    }
    
    private func addExistingBunkerAccount(pubkey:String, token:String) {
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: pubkey, context: viewContext)) {
            bunkerManager.connect(existingAccount, token: token)
            return
        }

        let account = CloudAccount(context: viewContext)
        account.createdAt = Date()
        account.publicKey = pubkey
//        NRState.shared.loadAccounts()
        bunkerManager.connect(account, token: token)
        return
    }
}

struct AddExistingAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            AddExistingAccountSheet()
        }
    }
}
