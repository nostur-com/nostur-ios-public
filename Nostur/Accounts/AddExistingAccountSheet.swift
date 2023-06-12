import SwiftUI

struct AddExistingAccountSheet: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) private var dismiss
    let sp:SocketPool = .shared
    @State var key = ""
    @State var invalidKey = false
    
    var offerTryOut = false
    var accentColor: Color = Color("AccentColor")
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
            ZStack {
                VStack {
                    TextField(String(localized:"Public or private key (npub or nsec)", comment:"Input field to enter public or private key on Add Existing Account screen"), text: $key)
                        .padding()
                        .background(grayBackground)
                        .cornerRadius(5.0)
                        .padding(.bottom, 20)
                    
                    Text("Keys are stored on your device in iOS keychain", comment:"Informational message about key storage on Add Existing Account screen").foregroundColor(.gray)
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
                            Text("Skip and try as guest first", comment: "Button to skip adding account and use the guest account instead")
                        }
                        .buttonStyle(.borderless)   
                        .padding(.top, 20)
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
    }
    
    func addExistingAccount(privkey:String) {
        guard let keys = try? NKeys(privateKeyHex: privkey) else {
            invalidKey = true
            key = ""
            return
        }
        
        if let existingAccount = (try? Account.fetchAccount(publicKey: keys.publicKeyHex(), context: viewContext)) {
            existingAccount.privateKey = keys.privateKeyHex()
            ns.setAccount(account: existingAccount)
            ns.onBoardingIsShown = false
            return
        }
        
        Importer.shared.existingIds.removeAll() // Because else we dont fetch new info... if we just fetched it before, maybe during onboarding
        
        
        let account = Account(context: viewContext)
        account.id = UUID()
        account.createdAt = Date()        
        account.publicKey = keys.publicKeyHex()
        account.privateKey = keys.privateKeyHex()
        
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
        ns.setAccount(account: account)
        ns.onBoardingIsShown = false
        
        do {
            try NewOnboardingTracker.shared.start(pubkey: account.publicKey)
        }
        catch {
            L.og.error("🔴🔴 Failed to start onboarding")
        }
    }
    
    func addExistingReadOnlyAccount(pubkey:String) {
        if let existingAccount = (try? Account.fetchAccount(publicKey: pubkey, context: viewContext)) {
            ns.setAccount(account: existingAccount)
            ns.onBoardingIsShown = false
            return
        }
        Importer.shared.existingIds.removeAll() // Because else we dont fetch new info... if we just fetched it before, maybe during onboarding
        let account = Account(context: viewContext)
        account.id = UUID()
        account.createdAt = Date()
        account.publicKey = pubkey
        
        
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
        
        do {
            try NewOnboardingTracker.shared.start(pubkey: account.publicKey)
        }
        catch {
            L.og.error("🔴🔴 Failed to start onboarding")
        }
    }
}

struct AddExistingAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            AddExistingAccountSheet()
        }
    }
}
