//
//  AddExistingAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI
import NostrEssentials

struct AddExistingAccountSheet: View {
    @Environment(\.showSidebar) @Binding var showSidebar
    @Environment(\.accountsState) var accountsState
    
    private var onDismiss: (() -> Void)?
    
    init(offerTryOut: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.offerTryOut = offerTryOut
        self.onDismiss = onDismiss
    }
    
    public var offerTryOut = false
    
    @EnvironmentObject private var themes: Themes
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var invalidKey = false
    
    
    private var grayBackground: Color = Color.white.opacity(0.3)
    private var isNsecbunkerKey: Bool {
        key.starts(with: "bunker://") ||
        (key.prefix(5) == "npub1" && (key.contains("#")) && key.split(separator: "#").count == 2 && key.split(separator: "#")[1].count == 64)
    }
    
    @ObservedObject private var bunkerManager = NSecBunkerManager.shared
    
    private var shouldDisableAddButton: Bool {
        isNsecbunkerKey && (bunkerManager.state == .connecting || bunkerManager.invalidRelayAddress)
    }
    
    var body: some View {
            ZStack {
                VStack {
                    if (key.isEmpty || key.lowercased().starts(with: "nsec1")) {
                        SecureField("", text: $key, prompt: Text("nostr address / npub / nsec / signer url", comment: "Input field to enter public or private key on Add Existing Account screen").foregroundColor(Color.black))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .padding()
                            .background(grayBackground)
                            .cornerRadius(5.0)
                            .padding(.bottom, 20)
                    }
                    else {
                        TextField("", text: $key, prompt: Text("nostr address / npub / nsec / signer url", comment: "Input field to enter public or private key on Add Existing Account screen").foregroundColor(Color.black))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .padding()
                            .background(grayBackground)
                            .cornerRadius(5.0)
                            .padding(.bottom, 20)
                            .disabled(bunkerManager.state == .connecting)
                    }
                    
                    if isNsecbunkerKey {
                        TextField(text: $bunkerManager.ncRelay) {
                            Text("Enter relay address")
                        }
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding()
                        .background(grayBackground)
                        .cornerRadius(5.0)
                        .padding(.bottom, 10)
                    }
                    
//                    Text("Keys are stored on your device in iOS keychain", comment:"Informational message about key storage on Add Existing Account screen").foregroundColor(.gray)
//                        .font(.caption2)
                    
                    Button {
                        if isNsecbunkerKey {
                            if let bunkerURL = parseBunkerUrl(key) {
                                guard isValidPubkey(bunkerURL.pubkey) else {
                                    invalidKey = true
                                    key = ""
                                    return
                                }
                                addExistingBunkerAccount(pubkey: bunkerURL.pubkey, token: bunkerURL.secret)
                            }
                            else {
                                guard key.split(separator: "#").count >= 2 else { return }
                                let bunkerNpub = String(key.split(separator: "#")[0])
                                let token = String(key.split(separator: "#")[1])
                                guard let nip19 = try? NIP19(displayString: bunkerNpub.replacingOccurrences(of: "-", with: "")) else {
                                    invalidKey = true
                                    key = ""
                                    return
                                }
                                addExistingBunkerAccount(pubkey: nip19.hexString, token: token)
                            }
                        }
                        else {
                            if (key.prefix(5) == "npub1") {
                                guard let nip19 = try? NIP19(displayString: key.replacingOccurrences(of: "-", with: "")) else {
                                    invalidKey = true
                                    key = ""
                                    return
                                }
                                addExistingReadOnlyAccount(pubkey: nip19.hexString)
                            }
                            else if (key.prefix(5) == "nsec1") {
                                guard let nip19 = try? NIP19(displayString: key.replacingOccurrences(of: "-", with: "")) else {
                                    invalidKey = true
                                    key = ""
                                    return
                                }
                                addExistingAccount(privkey: nip19.hexString)
                            }
                            else if (key.contains("@")) {
                                guard let nip05parts = try? NostrEssentials.parseNip05Address(key) else {
                                    invalidKey = true
                                    return
                                }
                                
                                Task { 
                                    do {
                                        let pubkey = try await NostrEssentials.fetchPubkey(from: nip05parts)
                                        addExistingReadOnlyAccount(pubkey: pubkey)
                                    } catch {
                                        invalidKey = true
                                    }
                                }
                            }
                            
                            showSidebar = false
                            dismiss()
                            onDismiss?()
                        }
                        
                    } label: {
                        if bunkerManager.state == .connecting {
                            CenteredProgressView()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                        }
                        else if (isNsecbunkerKey) {
                            Text("Add (Remote Signer)")
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
                    .fontWeightBold()
                    .tint(.black.opacity(0.65))
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .disabled(shouldDisableAddButton)
                    .opacity(shouldDisableAddButton ? 0.5 : 1.0)
                    
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
                    Text("Note: You can also add someone elses public key to try out Nostur from their perspective.", comment: "Informational message on Add Existing Account screen").opacity(0.7)
                }
            }
            .padding()
            .alert(String(localized:"Invalid key", comment: "Message shown when user has entered an invalid key"), isPresented: $invalidKey) {
                Button("OK", role: .cancel) { }
            }
                        .navigationTitle(String(localized:"Add existing account", comment: "Navigation title for Add Existing Account screen"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: key) { newKey in
                if isNsecbunkerKey {
                    if let bunkerURL = parseBunkerUrl(newKey)?.relay {
                        bunkerManager.ncRelay = bunkerURL
                    }
                    else {
                        bunkerManager.ncRelay = ""
                    }
                }
                else {
                    bunkerManager.ncRelay = ""
                }
            }
            .onChange(of: bunkerManager.state) { bunkerState in
                if bunkerState == .connected {
                    guard let account = bunkerManager.account else { return }
                    account.ncRelay = bunkerManager.ncRelay
                    
                    let pubkey = account.publicKey
                    
                    // Continue onboarding..
                    
                    let bgContext = bg()
                    bgContext.perform {
                    
                        // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
                        if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: pubkey, context: bgContext) {
                            for contactEvent in contactEvents {
                                let eventId = contactEvent.id
                                Importer.shared.existingIds.removeValue(forKey: eventId)
                                bgContext.delete(contactEvent)
                            }
                        }
                        
                        // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
                        if let clEvents = Event.contactListEvents(byAuthorPubkey: pubkey, context: bgContext) {
                            for clEvent in clEvents {
                                let eventId = clEvent.id
                                Importer.shared.existingIds.removeValue(forKey: eventId)
                                bgContext.delete(clEvent)
                            }
                        }
                        
                        if bgContext.hasChanges {
                            try? bgContext.save()
                        }
                        
                        DispatchQueue.main.async {
                            accountsState.changeAccount(account)
                            showSidebar = false
                            dismiss()
                            onDismiss?()
                            
                            do {
                                try NewOnboardingTracker.shared.start(pubkey: pubkey)
                            }
                            catch {
                                L.og.error("🔴🔴 Failed to start onboarding")
                            }
                        }
                    }
                }
                else if bunkerState == .error {
                    if let account = bunkerManager.account {
                        NIP46SecretManager.shared.deleteSecret(account: account)
                        viewContext.delete(account)
                    }
                }
            }
            .onAppear {
                if bunkerManager.state == .error {
                    bunkerManager.state = .disconnected
                }
            }
            .wowBackground()
    }
    
    private func addExistingAccount(privkey: String) {
        guard let keys = try? Keys(privateKeyHex: privkey) else {
            invalidKey = true
            key = ""
            return
        }
        
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: keys.publicKeyHex, context: viewContext)) {
            existingAccount.privateKey = keys.privateKeyHex
            existingAccount.isNC = false
            existingAccount.flagsSet.insert("full_account")
            accountsState.changeAccount(existingAccount)
            showSidebar = false
            dismiss()
            onDismiss?()
            return
        }
        
        let account = CloudAccount(context: viewContext)
        account.createdAt = Date()        
        account.publicKey = keys.publicKeyHex
        account.privateKey = keys.privateKeyHex
        account.flags = "full_account"
        
        try? viewContext.save()
        L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
        
        let pubkey = account.publicKey
        
        let bgContext = bg()
        bgContext.perform {
            
            // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
            if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: pubkey, context: bgContext) {
                for contactEvent in contactEvents {
                    let eventId = contactEvent.id
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                    bgContext.delete(contactEvent)
                }
            }
            
            // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
            if let clEvents = Event.contactListEvents(byAuthorPubkey: pubkey, context: bgContext) {
                for clEvent in clEvents {
                    let eventId = clEvent.id
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                    bgContext.delete(clEvent)
                }
            }
            
            if bgContext.hasChanges {
                try? bgContext.save()
            }
            
            DispatchQueue.main.async {
                accountsState.changeAccount(account)
                showSidebar = false
                dismiss()
                onDismiss?()
                
                do {
                    try NewOnboardingTracker.shared.start(pubkey: pubkey)
                }
                catch {
                    L.og.error("🔴🔴 Failed to start onboarding")
                }
            }
        }
    }
    
    private func addExistingReadOnlyAccount(pubkey: String) {
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: pubkey, context: viewContext)) {
            accountsState.changeAccount(existingAccount)
            showSidebar = false
            dismiss()
            onDismiss?()
            return
        }

        let account = CloudAccount(context: viewContext)
        account.createdAt = Date()
        account.publicKey = pubkey
        
        try? viewContext.save()
        L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
        
        let bgContext = bg()
        bgContext.perform {
            
            // Remove existing metadata events, so can proper parse again from Importers. Else get filtered by duplicate filter
            if let contactEvents = Event.setMetaDataEvents(byAuthorPubkey: pubkey, context: bgContext) {
                for contactEvent in contactEvents {
                    let eventId = contactEvent.id
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                    bgContext.delete(contactEvent)
                }
            }
            
            // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
            if let clEvents = Event.contactListEvents(byAuthorPubkey: pubkey, context: bgContext) {
                for clEvent in clEvents {
                    let eventId = clEvent.id
                    Importer.shared.existingIds.removeValue(forKey: eventId)
                    bgContext.delete(clEvent)
                }
            }
            
            if bgContext.hasChanges {
                try? bgContext.save()
            }
            
            DispatchQueue.main.async {
                accountsState.changeAccount(account)
                showSidebar = false
                dismiss()
                onDismiss?()
                
                do {
                    try NewOnboardingTracker.shared.start(pubkey: pubkey)
                }
                catch {
                    L.og.error("🔴🔴 Failed to start onboarding")
                }
            }
        }
    }
    
    private func addExistingBunkerAccount(pubkey: String, token: String? = nil) {
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: pubkey, context: viewContext)) {
            existingAccount.flagsSet.insert("full_account")
            bunkerManager.connect(existingAccount, token: token)
            return
        }

        let account = CloudAccount(context: viewContext)
        account.flags = "full_account"
        account.createdAt = Date()
        
        // NIP-46 user-pubkey. This one can change after we call get_public_key on bunker
        account.publicKey = pubkey
        
        // NIP-46 remote-signer-pubkey
        account.ncRemoteSignerPubkey_ = pubkey
        account.ncRelay = bunkerManager.ncRelay
        bunkerManager.connect(account, token: token)
 
        accountsState.changeAccount(account)
        showSidebar = false
        dismiss()
        onDismiss?()
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
