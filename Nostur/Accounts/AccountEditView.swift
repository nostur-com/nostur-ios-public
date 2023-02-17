//
//  AccountView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI
import CoreData
import SwiftyJSON

struct AccountEditView: View {
    
    var sp:SocketPool = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var up:Unpublisher
    @EnvironmentObject var ns:NosturState
    @ObservedObject var account: Account
    @State var newPrivateKey = ""
    @State var contactsPresented = false
    @State var invalidPrivateKey = false
    
    var body: some View {
        let shouldDisable = account.privateKey == nil || account.privateKey == ""
        VStack {
//            Button { contactsPresented = true } label: {
//                NavigationLink(value: ViewPath.Following(account:account)) {
//                    Text("Following \(account.follows?.count ?? 0)")
//                }
//            }
            
            Form {
                
                Section(header: Text("Your name") ) {
                    TextField("Enter your name", text: $account.display_name).disabled(shouldDisable)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Your username") ) {
                    TextField("Enter your username", text: $account.name).disabled(shouldDisable)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section(header: Text("Bio") ) {
                    TextField("Something about yourself", text:$account.about, axis: .vertical)
                        .lineLimit(3...5)
                        .disabled(shouldDisable)
                }
                
                Section(header: Text("NIP-05 identifier") ) {
                    TextField("", text: $account.nip05).keyboardType(.emailAddress).disabled(shouldDisable)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section(header: Text("Lightning Address (LUD-16)") ) {
                    TextField("", text: $account.lud16).keyboardType(.emailAddress).disabled(shouldDisable)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section(header: Text("Profile picture URL") ) {
                    TextField("https://nostur.com/profile.jpg", text: $account.picture).keyboardType(.URL).disabled(shouldDisable)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section(header: Text("Profile banner URL") ) {
                    TextField("https://nostur.com/banner.jpg", text: $account.banner).keyboardType(.URL).disabled(shouldDisable)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
                
                if (shouldDisable) {
                    Section(header:Text("Import private key")) {
                        TextField("nsec1...", text: $newPrivateKey).foregroundColor(.primary)
                            .keyboardType(.URL)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                    }.foregroundColor(.primary)
                }
                
                Section(header: Text(shouldDisable ? "Public key" : "Keys") ) {
                    HStack {
                        Text("**PUBLIC KEY:** \(account.npub)").lineLimit(1)
                        Image(systemName: "doc.on.doc.fill")
                            .onTapGesture {
                                UIPasteboard.general.string = account.npub
                            }
                    }
                    
                    if (!shouldDisable && account.nsec != nil) {
                        HStack {
                            Text("**PRIVATE KEY:** \(String(account.nsec!.prefix(7)))∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗").lineLimit(1)
                            Image(systemName: "doc.on.doc.fill")
                                .onTapGesture {
                                    UIPasteboard.general.string = account.nsec!
                                }
                        }
                    }
                }
            }
            .foregroundColor(shouldDisable ? .gray : .primary)
            
            
//            Button {
//                fetchContacts(account:account)
//            } label: {
//                Text("Load contacts from relays")
//            }
//            Button {
//                updateContacts()
//            } label: {
//                Text("Update contacts metadata")
//            }
//            Button {
//                loadFollowers(account: account)
//            } label: {
//                Text("load followers from kind 3")
//            }
            

        }
        .onAppear {
            if (account.privateKey == nil) {
                let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: account.publicKey!))
                sp.sendMessage(message)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if newPrivateKey != "" { // TODO: Handle nsec format
                    
                    guard let nip19 = try? NIP19(displayString: newPrivateKey) else {
                        invalidPrivateKey = true
                        newPrivateKey = ""
                        return
                    }
                    guard let keys = try? NKeys(privateKeyHex: nip19.hexString) else {
                        invalidPrivateKey = true
                        newPrivateKey = ""
                        return
                    }
                    
                    guard (keys.publicKeyHex() == account.publicKey!) else {
                        invalidPrivateKey = true
                        newPrivateKey = ""
                        return
                    }

                    account.privateKey = keys.privateKeyHex()
                }
                do {
                    try viewContext.save()
                    try publishMetadataEvent()
                    dismiss()
                }
                catch {
                    print("Error saving account")
                }
            } label: {
                Text("Save").frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .alert("Invalid private key", isPresented: $invalidPrivateKey) {
                        Button("OK", role: .cancel) { }
                    }
        }
        .background(.regularMaterial)
        .navigationDestination(isPresented: $contactsPresented) {
            AccountFollowingList(account: account)
        }
    }
}

extension AccountEditView {
    func saveAccount() throws {
        
    }
    
    // TODO: MOVE TO Event Publisher class
    func publishMetadataEvent() throws {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }
        if account.banner != "" { setMetadataContent.banner = account.banner }
        if account.display_name != "" { setMetadataContent.display_name = account.display_name }
        
        if (account.privateKey != nil) {
            do {
                let keys = try NKeys(privateKeyHex: account.privateKey!)
                
                var newKind0Event = NEvent(content: setMetadataContent)
                
                let newKind0EventSigned = try newKind0Event.sign(keys)
                
                print(newKind0EventSigned.eventJson())
                print(newKind0EventSigned.wrappedEventJson())
                
                _ = Event.saveEvent(event: newKind0EventSigned, context: viewContext)
                Contact.saveOrUpdateContact(event: newKind0EventSigned, context: viewContext)
                try viewContext.save()
                
                // broadcast to relays
                up.publishNow(newKind0EventSigned)
            }
            catch {
                print("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
            }
        }
    }
    
    func fetchContacts(account:Account) {
        if (account.publicKey != nil) {
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: account.publicKey!)))
        }
    }
    
    func loadFollowers(account:Account) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", account.publicKey!)
        let clEvent = try! viewContext.fetch(fr).first
        if (clEvent != nil) {
            
        
            let contactPubkeys = TagsHelpers(clEvent?.tags() ?? []).pTags().map { $0.pubkey }
            
            let cr = Contact.fetchRequest()
            cr.predicate = NSPredicate(format: "pubkey IN %@", contactPubkeys)
            let contacts = try! viewContext.fetch(cr)
            
            for contact in contacts {
                account.addToFollows(contact)
                print("Adding to followers: \(contact.name ?? "??")")
            }
            ns.objectWillChange.send()
            try! viewContext.save();
        }
    }
    
    func updateContacts() { // move this method to somewhere more global maybe
        let pubkeys = account.follows?.map { $0.pubkey! }
        if (pubkeys != nil) {
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys!)))
        }
    }
}



struct AccountView_Previews: PreviewProvider {
    static var previews: some View {
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
            NavigationStack {
                AccountEditView(account: account!)
                    .withPreviewEnvironment()
            }
    }
}
