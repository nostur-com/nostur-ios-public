//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct EditNosturList: View {
    @ObservedObject public var list: CloudFeed
    
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    
    @State private var confirmDeleteShown = false
    @State private var contactToRemove: Contact? = nil
    @State private var addContactsSheetShown = false
    @State private var editList: CloudFeed? = nil
    @State private var selectedContacts: Set<Contact> = []
    @State private var listNRContacts: [NRContact] = []
    @State private var wasShared: Bool = false
    @State private var listNaddr: String? = nil
    
    var body: some View {
        List {
            Section(header: Text("Feed settings", comment: "Header for entering title of a feed")) {
                Group {
                    Toggle(isOn: $list.showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
                    
                    if list.showAsTab {
                        VStack(alignment: .leading) {
                            TextField(String(localized:"Tab title", comment:"Placeholder for input field to enter title of a feed"), text: $list.name_)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            
                            Text("Shown in the tab bar (not public)")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
                .listRowBackground(themes.theme.listBackground)
            }
            
            Section(header: Text("Share list", comment: "Header of Feed/List sharing settings")) {
                Group {
                    VStack(alignment: .leading) {
                        Toggle(isOn: $list.sharedList, label: { Text("Make list public", comment: "Toggle to make list public")})
                            .disabled(!list.sharedList && list.contactPubkeys.isEmpty)
                        if list.aTag != nil, let listNaddr = listNaddr {
                            CopyableTextView(text: "Public list address: \(listNaddr)", copyText: "nostr:\(listNaddr)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                                .padding(.trailing, 70)
                        }
                        else {
                            Text("Creates a public list on nostr relays")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                        }
                    }

                    if list.sharedList {
                        VStack(alignment: .leading) {
                            TextField(String(localized: "Title", comment:"Placeholder for input field to enter title of a shared list"), text: $list.sharedTitle_)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .onAppear {
                                    if list.sharedTitle_.isEmpty {
                                        list.sharedTitle_ = list.name_
                                    }
                                }
                            Text("Share this list with a different title")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                        }
                        
                        ListAccountPicker(accountPubkey: $list.accountPubkey)
                            .disabled(list.aTag != nil)
                    }
                }
                .listRowBackground(themes.theme.listBackground)
            }
            
            Section {
                ForEach(listNRContacts) { nrContact in
                    NRContactSearchResultRow(nrContact: nrContact)
                        .padding()
                        .onTapGesture { navigateTo(NRContactPath(nrContact: nrContact)) }
                        .listRowInsets(EdgeInsets())
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                list.contactPubkeys.remove(nrContact.pubkey)
                                listNRContacts.removeAll(where: { $0.pubkey == nrContact.pubkey })
                                DataProvider.shared().save()
                                sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: list.contactPubkeys))
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            
                        }
                        .listRowBackground(themes.theme.listBackground)
                }
            } header: {
                Text("Contacts in list")
            }
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(themes.theme.background)
        .nosturNavBgCompat(themes: themes)
        .navigationTitle("\(list.name ?? "feed")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "\(list.name ?? "feed")")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add contact", systemImage: "plus") {
                    addContactsSheetShown = true
                }
                .labelStyle(.iconOnly)

            }
        }
        .sheet(isPresented: $addContactsSheetShown) {
            NBNavigationStack {
                ContactsSearch(followingPubkeys: follows(),
                               prompt: "Search", onSelectContacts: { selectedContacts in
                    list.contactPubkeys.formUnion(Set(selectedContacts.map { $0.pubkey }))
                    addContactsSheetShown = false
                    let listContactPubkeys = list.contactPubkeys
                    bg().perform {
                        let listNRContacts: [NRContact] = Contact.fetchByPubkeys(listContactPubkeys)
                            .compactMap { NRContact.fetch($0.pubkey, contact: $0) }
                        Task { @MainActor in
                            self.listNRContacts = listNRContacts
                        }
                    }
                    DataProvider.shared().save()
                    sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: list.contactPubkeys))
                })
                .equatable()
                .navigationTitle(String(localized:"Add contacts", comment:"Navigation title of sheet to add contacts to feed"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            addContactsSheetShown = false
                        }
                    }
                }
                .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .onAppear {
            let listContactPubkeys = list.contactPubkeys
            wasShared = list.sharedList
            let aTag = list.aTag
            bg().perform {
                let listNRContacts: [NRContact] = Contact.fetchByPubkeys(listContactPubkeys)
                    .compactMap { NRContact.fetch($0.pubkey, contact: $0) }
                
                Task { @MainActor in
                    self.listNRContacts = listNRContacts
                }
                
                if let aTag {
                    let relaysForHint: Set<String> = resolveRelayHint(forPubkey: aTag.pubkey)
                    if let si = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(aTag.kind), pubkey: aTag.pubkey, dTag: aTag.definition, relays: Array(relaysForHint)) {
                        Task { @MainActor in
                            listNaddr = si.identifier
                        }
                    }
                }
            }
        }
        
        .onDisappear {
            // if list is public, publish....
            
            if list.sharedList,
               let accountPubkey = list.accountPubkey,
               let fullAccount = AccountsState.shared.accounts.first(where: { $0.publicKey ==  accountPubkey })
            {
                publishList(list, account: fullAccount)
            }
            else if let accountPubkey = list.accountPubkey, list.aTag != nil && !list.sharedList && wasShared, let fullAccount = AccountsState.shared.accounts.first(where: { $0.publicKey ==  accountPubkey }) {
                // No longer shared
                
                // set 0 p tags and send delete request
                clearAndDeleteList(list, account: fullAccount)
            }
        }
        
    }
}

func publishList(_ feed: CloudFeed, account: CloudAccount) {
    var nEvent = NEvent(content: "")
    nEvent.kind = .followSet
    nEvent.publicKey = account.publicKey
    nEvent.createdAt = NTimestamp.init(date: Date())
    nEvent.tags.append(NostrTag(["title", feed.sharedTitle_]))
    
    // Keep linked to existing aTag / listId
    if let aTag = feed.aTag, aTag.pubkey == account.publicKey {
        nEvent.tags.append(NostrTag(["d", aTag.definition]))
    }
    else { // First time, create new aTag and store in listId to keep CloudFeed linked to kind:30000 nostr list
        let aTag = ATag(kind: 30000, pubkey: account.publicKey, definition: feed.id?.uuidString ?? UUID().uuidString)
        feed.listId = aTag.aTag
        viewContextSave()
        nEvent.tags.append(NostrTag(["d", aTag.definition]))
    }
    
    // Add the contacts
    feed.contactPubkeys.forEach { pTag in
        nEvent.tags.append(NostrTag(["p", pTag]))
    }
    
    // Include client meta data if enabled
    if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
        nEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
    }
    
    if account.isNC {
        nEvent = nEvent.withId()
        
        // Save unsigned event:
        let bgContext = bg()
        bgContext.perform {
            let savedEvent = Event.saveEvent(event: nEvent, flags: "nsecbunker_unsigned", context: bgContext)
            DataProvider.shared().bgSave()
            
            DispatchQueue.main.async {
                NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                    bg().perform {
                        savedEvent.sig = signedEvent.signature
                        savedEvent.flags = "awaiting_send"
                        DispatchQueue.main.async {
                            _ = Unpublisher.shared.publish(signedEvent)
                        }
                    }
                })
            }
        }
    }
    else if let signedEvent = try? account.signEvent(nEvent) {
        let bgContext = bg()
        bgContext.perform {
            _ = Event.saveEvent(event: signedEvent, flags: "awaiting_send", context: bgContext)
            DataProvider.shared().bgSave()
        }
        _ = Unpublisher.shared.publish(signedEvent)
    }
    
}

func clearAndDeleteList(_ feed: CloudFeed, account: CloudAccount) {
    var nEvent = NEvent(content: "")
    nEvent.kind = .followSet
    nEvent.publicKey = account.publicKey
    nEvent.createdAt = NTimestamp.init(date: Date.now.addingTimeInterval(-3)) // needs to be earlier than delete request
    nEvent.tags.append(NostrTag(["title", ""]))
    
    // aTag must be there or there is nothing to clear / delete
    guard let aTag = feed.aTag, aTag.pubkey == account.publicKey else { return }
    nEvent.tags.append(NostrTag(["d", aTag.definition]))
    
    // Note no more contacts / p-tags
   
    // Include client meta data if enabled
    if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
        nEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
    }
    
    
    var deleteReq = NEvent(content: "")
    deleteReq.kind = .delete
    deleteReq.publicKey = account.publicKey
    deleteReq.createdAt = NTimestamp.init(date: Date())
    deleteReq.tags.append(NostrTag(["a", aTag.aTag]))
    deleteReq.tags.append(NostrTag(["k", "30000"]))
    
    
    if account.isNC {
        nEvent = nEvent.withId()
        deleteReq = deleteReq.withId()
        
        // Save unsigned event:
        let bgContext = bg()
        bgContext.perform {
            let savedEvent = Event.saveEvent(event: nEvent, flags: "nsecbunker_unsigned", context: bgContext)
            let savedEvent2 = Event.saveEvent(event: deleteReq, flags: "nsecbunker_unsigned", context: bgContext)
            savedEvent.deletedById = savedEvent2.id
            DataProvider.shared().bgSave()
            
            DispatchQueue.main.async {
                NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                    bg().perform {
                        savedEvent.sig = signedEvent.signature
                        savedEvent.flags = "awaiting_send"
                        DispatchQueue.main.async {
                            Unpublisher.shared.publishNow(signedEvent)
                        }
                    }
                })
                NSecBunkerManager.shared.requestSignature(forEvent: deleteReq, usingAccount: account, whenSigned: { signedEvent in
                    bg().perform {
                        savedEvent.sig = signedEvent.signature
                        savedEvent.flags = "awaiting_send"
                        DispatchQueue.main.async {
                            _ = Unpublisher.shared.publish(signedEvent)
                        }
                    }
                })
            }
        }
    }
    else {
        if let signedDeleteEvent = try? account.signEvent(deleteReq) {
            let deleteEventId = signedDeleteEvent.id
            let bgContext = bg()
            bgContext.perform {
                _ = Event.saveEvent(event: signedDeleteEvent, flags: "awaiting_send", context: bgContext)
                DataProvider.shared().bgSave()
            }
            _ = Unpublisher.shared.publish(signedDeleteEvent) // is published after wipe event (timer)
            
            if let signedWipedEvent = try? account.signEvent(nEvent) {
                let bgContext = bg()
                bgContext.perform {
                    let wipedEvent = Event.saveEvent(event: signedWipedEvent, flags: "awaiting_send", context: bgContext)
                    wipedEvent.deletedById = deleteEventId
                    DataProvider.shared().bgSave()
                    Task { @MainActor in
                        ViewUpdates.shared.postDeleted.send((wipedEvent.id, deleteEventId))
                    }
                }
                Unpublisher.shared.publishNow(signedWipedEvent) // is published before delete req (Now)
            }
            
        }
    }
    
}

struct EditList_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadCloudFeeds()
        }) {
            NBNavigationStack {
                if let list = PreviewFetcher.fetchList() {
                    EditNosturList(list: list)
                        .withNavigationDestinations()
                }
            }
        }
    }
}


struct ListAccountPicker: View {
    @EnvironmentObject private var themes: Themes
    @Binding var accountPubkey: String?
    @State var accounts: [CloudAccount] = []

    var body: some View {
        Picker(selection: $accountPubkey) {
            ForEach(accounts) { account in
                HStack {
                    PFP(pubkey: account.publicKey, account: account, size: 20.0)
                    Text(account.anyName)
                }
                .tag(account.publicKey)
                .foregroundColor(themes.theme.primary)
            }
            
        } label: {
            Text("Account")
        }
        .pickerStyleCompatNavigationLink()
        .task {
            accounts = AccountsState.shared.accounts
                .filter { $0.isFullAccount }
            if accountPubkey == nil {
                accountPubkey = AccountsState.shared.activeAccountPublicKey
            }
        }
    }
}

import NavigationBackport

#Preview {
    PreviewContainer({ pe in pe.loadAccounts() }) {
        NBNavigationStack {
            Form {
                Section(header: Text("Main WoT", comment:"Setting heading on settings screen")) {
                    MainWoTaccountPicker()
                }
            }
        }
    }
}
