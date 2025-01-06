//
//  AccountEditView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI
import CoreData
import Combine
import Nuke
import NukeUI
import CryptoKit
import NavigationBackport
import NostrEssentials

struct AccountEditView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    private let up: Unpublisher = .shared
    @ObservedObject private var account: CloudAccount
    @State private var newPrivateKey = ""
    @State private var contactsPresented = false
    @State private var invalidPrivateKey = false
    @State private var uploading = false
    @State private var uploadError:String?
    @State private var subscriptions = Set<AnyCancellable>()
    @State private var newPicture: UIImage?
    @State private var newBanner: UIImage?
    @State private var anyLud = ""
    
    init(account: CloudAccount) {
        self.account = account
    }
    
    var body: some View {
        let shouldDisable = account.privateKey == nil || account.privateKey == ""
        GeometryReader { geo in
            VStack {
                ZStack {
                    if #available(iOS 16.0, *) {
                        BannerPicPicker($account.banner, newPicture: $newBanner, width: geo.size.width)
                            .frame(height: 150)
                            .clipped()
                    }
                    HStack {
                        if #available(iOS 16.0, *) {
                            ProfilePicPicker($account.picture, newPicture: $newPicture)
                                .offset(x: 20, y: 60)
                        }
                        else {
                            PFP(pubkey: account.publicKey, account: account, size: 75)
                                .offset(x: 20, y: 60)
                        }
                        
                        Spacer()
                    }
                }
                .listRowBackground(Color(.systemGroupedBackground))
                ZStack {
                    Form {
                        
                        Group {
                            Section(header: Text("Your name", comment: "Label for entering your name on Edit Profile screen") ) {
                                TextField(String(localized:"Enter your name", comment:"Placeholder on input field on Edit Profile screen"), text: $account.name).disabled(shouldDisable)
                                    .disableAutocorrection(true)
                            }
                            
                            Section(header: Text("Bio", comment: "Label for entering a bio about yourself on Edit Profile screen") ) {
                                if #available(iOS 16.0, *) {
                                    TextField(String(localized:"Something about yourself", comment:"Placeholder on input field for Bio on Edit Profile screen"), text: $account.about, axis: .vertical)
                                        .lineLimit(3...5)
                                        .disabled(shouldDisable)
                                }
                                else {
                                    TextField(String(localized:"Something about yourself", comment:"Placeholder on input field for Bio on Edit Profile screen"), text: $account.about)
                                        .lineLimit(3)
                                        .disabled(shouldDisable)
                                }
                            }
                            
                            Section(header: Text("Nostr address (NIP-05)", comment: "Label for entering a NIP-05 username on Edit Profile screen") ) {
                                TextField("", text: $account.nip05).keyboardType(.emailAddress).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        //                    .listRowInsets(EdgeInsets())
                        
                        Section(header: Text("Lightning Address (LUD-06/16)", comment: "Label for entering a Lightning Address on Edit Profile screen") ) {
                            TextField("", text: $anyLud).keyboardType(.emailAddress).disabled(shouldDisable)
                                .keyboardType(.URL)
                                .disableAutocorrection(true)
                                .textInputAutocapitalization(.never)
                        }
                        
                        if (newPicture == nil) {
                            Section(header: Text("Profile picture URL", comment: "Label for entering an URL to profile picture on Edit Profile screen") ) {
                                TextField(String("https://nostur.com/profile.jpg"), text: $account.picture).keyboardType(.URL).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        
                        if (newBanner == nil) {
                            Section(header: Text("Profile banner URL", comment: "Label for entering an URL to profile banner on Edit Profile screen") ) {
                                TextField(String("https://nostur.com/banner.jpg"), text: $account.banner).keyboardType(.URL).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        
                        if (shouldDisable) {
                            Section(header:Text("Import private key", comment: "Label for importing your private key on Edit Profile screen")) {
                                TextField(String("nsec1..."), text: $newPrivateKey).foregroundColor(.primary)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }.foregroundColor(.primary)
                        }
                        
                        Section(header: Text(shouldDisable ? "Public key" : "Keys", comment: "Header above private and public key on Edit Profile screen") ) {
                            HStack {
                                Text("**PUBLIC KEY:** \(account.npub)", comment: "Field that shows a public key").lineLimit(1)
                                Image(systemName: "doc.on.doc.fill")
                                    .onTapGesture {
                                        UIPasteboard.general.string = account.npub
                                        sendNotification(.anyStatus, (String(localized: "Public key copied to clipboard", comment: "Notification shown after user tapped to copy"), "COPYKEYS"))
                                    }
                            }
                            
                            if (!shouldDisable && account.nsec != nil) && !account.isNC {
                                HStack {
                                    Text("**PRIVATE KEY:** \(String(account.nsec!.prefix(7)))∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗", comment: "Field that shows a partial private key").lineLimit(1)
                                    Spacer()
                                    Image(systemName: "doc.on.doc.fill")
                                        .onTapGesture {
                                            UIPasteboard.general.string = account.nsec!
                                            sendNotification(.anyStatus, (String(localized:"Private key copied to clipboard", comment:"Notification shown after user tapped to copy"), "COPYKEYS"))
                                        }
                                }
                            }
                        }
                    }
                    .foregroundColor(shouldDisable ? .gray : .primary)
                    .padding(.top, 20)
                    
                    VStack {
                        Spacer()
                        AnyStatus(filter: "COPYKEYS")
                            .opacity(0.85)
                    }
                }
//                Button {
//                    loadFromRelays()
//                } label: {
//                    Text("Load info and contacts from relays")
//                        .foregroundColor(Color.primary)
//                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized:"Edit profile", comment: "Navigation title for Edit Profile screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .principal) {
                if let uploadError {
                    Text(uploadError).foregroundColor(.red)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if newPicture != nil || newBanner != nil {
                        uploading = true
                        uploadBannerOrProfilePic(pfp: newPicture, banner: newBanner)
                            .receive(on: RunLoop.main)
                            .sink(receiveCompletion: { result in
                                switch result {
                                case .failure(let error):
                                    L.og.error("Error uploading images: \(error.localizedDescription)")
                                    uploadError = "Image upload error"
                                    sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                                    uploading = false
                                case .finished:
                                    L.og.info("PFP uploaded successfully")
                                }
                            }, receiveValue: { urls in
//                                print(urls)
                                for url in urls {
                                    if url.contains("/banner.") {
                                        account.banner = url
                                    }
                                    if url.contains("/profilepic.") {
                                        account.picture = url
                                    }
                                }
                                save()
                                uploading = false
                            })
                            .store(in: &subscriptions)
                    }
                    else {
                        save()
                    }
                } label: {
                    if uploading {
                        ProgressView()
                    }
                    else {
                        Text("Save", comment: "Save button on the Edit Profile screen")
                    }
                }
                .disabled(uploading)
            }
        }
        .alert(String(localized:"Invalid private key", comment:"Message shown after user entered an invalid private key"), isPresented: $invalidPrivateKey) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            if account.lud16.contains("@") {
                anyLud = account.lud16
            }
            else if !account.lud06.isEmpty {
                anyLud = account.lud06
            }
            
            if (account.privateKey == nil) {
                req(RM.getUserMetadata(pubkey: account.publicKey))
            }
        }
    }
}

extension AccountEditView {
    
    private func save() {
        if newPrivateKey != "" {
            
            guard let nip19 = try? NIP19(displayString: newPrivateKey) else {
                invalidPrivateKey = true
                newPrivateKey = ""
                return
            }
            guard let keys = try? Keys(privateKeyHex: nip19.hexString) else {
                invalidPrivateKey = true
                newPrivateKey = ""
                return
            }
            
            guard (keys.publicKeyHex == account.publicKey) else {
                invalidPrivateKey = true
                newPrivateKey = ""
                return
            }
            
            account.privateKey = keys.privateKeyHex
        }
        do {
            if anyLud.contains("@") { // email-like address entered
                account.lud16 = anyLud.replacingOccurrences(of: "mailto:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                account.lud06 = ""
            }
            else if !anyLud.isEmpty { // lnurl entered
                account.lud16 = ""
                account.lud06 = anyLud.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            else { // nothing entered
                account.lud16 = ""
                account.lud06 = ""
            }
            try publishMetadataEvent(account)
            
            // update zapper pubkey if lud16 changed
            updateZapperPubkey()
            dismiss()
        }
        catch {
            L.og.error("Error saving account")
        }
    }
    
    private func updateZapperPubkey() {
        guard account.lud16 != "" else { return }
        guard let contact = Contact.fetchByPubkey(account.publicKey, context: viewContext) else { return }
        guard let contactLud16 = contact.lud16, contactLud16 != account.lud16 else { return }
        
        Task {
            let response = try await LUD16.getCallbackUrl(lud16: account.lud16)
            if let zapperPubkey = response.nostrPubkey, (response.allowsNostr ?? false) {
                DispatchQueue.main.async {
                    contact.zapperPubkey = zapperPubkey
                }
                L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
            }
        }
    }
    
    private func loadFromRelays() {
        // 1. Prefill from cached event (if in cache)
        CloudAccount.preFillReadOnlyAccountInfo(account: account, context: viewContext, forceOverwrite: true)
        CloudAccount.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
        
        req(RM.getUserMetadataAndContactList(pubkey: account.publicKey))
    }
    
    private func loadFollowers(account: CloudAccount) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", account.publicKey)
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let clEvent = try! viewContext.fetch(fr).first
        if (clEvent != nil) {
            
            let contactPubkeys = TagsHelpers(clEvent?.tags() ?? []).pTags().map { $0.pubkey }
            
            let cr = Contact.fetchRequest()
            cr.predicate = NSPredicate(format: "pubkey IN %@", contactPubkeys)
            let contacts = try! viewContext.fetch(cr)
            
            for contact in contacts {
                account.followingPubkeys.insert(contact.pubkey)
//                print("Adding to followers: \(contact.name ?? "??")")
            }
            viewContextSave()
        }
    }
    
    private func updateContacts() { // move this method to somewhere more global maybe
        let pubkeys = Array(account.followingPubkeys)
        if (!pubkeys.isEmpty) {
            req(RM.getUserMetadata(pubkeys: pubkeys))
        }
    }
}


#Preview {
    let fab = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
    
    return PreviewContainer {
        NBNavigationStack {
            if let account = PreviewFetcher.fetchAccount(fab, context: DataProvider.shared().container.viewContext) {
                AccountEditView(account: account)
            }
        }
        .nbUseNavigationStack(.never)
    }
}





