//
//  ContactFeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2025.
//

import SwiftUI
import NostrEssentials
import NavigationBackport

// Settings for a local private list or public nip-51 list
struct ContactFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var la: LoggedInAccount
    
    @State private var accounts: [CloudAccount] = []
    @State private var listNaddr: String? = nil
    @State private var wasShared: Bool = false
    @State private var listNRContacts: [NRContact] = []
    @State private var addContactsSheetShown = false
    
    private var isPublicNIP51List: Bool {
        feed.sharedList
    }
    private var isOwnManagedList: Bool {
        feed.accountPubkey != nil && (feed.type == "pubkeys" || feed.type == nil) && feed.listId != nil
    }
    
    private var isOwnList: Bool {
        if ((feed.type == "pubkeys" || feed.type == nil) && feed.listId == nil) {
            return true
        }
        
        if (feed.type == CloudFeedType.followPack.rawValue || feed.type == CloudFeedType.followSet.rawValue),
           let aTag = feed.aTag,
           AccountsState.shared.fullAccounts.contains(where: { $0.publicKey == aTag.pubkey }) {
               return true
        }
        
        return false
    }
    
    var body: some View {
        NXForm {
            // Managed by someone else, with toggle subscribe on/off (switchs between "pubkeys" and "30000"/"39089")
            if !isOwnList, let aTag = feed.aTag {
                // feedSettingsSection
                 
                 // Even if we change from 30000 to own pubkeys sheet, still show where the list came from, also makes easy to toggle on off subscribe updates again.
             
                 // Feed managed by... zap author...
                 Section {
                     ListManagedByView(feed: feed, aTag: aTag, parentDismiss: dismiss)
                         .padding(.vertical, 10)
                         .listRowInsets(EdgeInsets())
                         .padding(.horizontal, 20)
                 }
                 
                 Section {
                     // Copy to own feed. No longer managed
                     Toggle(isOn: Binding(get: {
                         feed.type == "30000" || feed.type == "39089"
                     }, set: { newValue in
                         if newValue {
                             feed.type = aTag.kind == 30000 ? "30000" : "39089"
                         }
                         else {
                             feed.type = "pubkeys"
                         }
                     })) {
                         Text("Subscribe to list updates")
                     }
                 } footer: {
                     Text("Updates refer to people added or removed from this list, not posts or content.")
                         .font(.footnote)
                 }
                
                // TOGLE PIN ON TAB BAR
                Toggle(isOn: $feed.showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
                
                // TAB TITLE TEXTFIELD
                if feed.showAsTab {
                    VStack(alignment: .leading) {
                        TextField(String(localized:"Tab title", comment:"Placeholder for input field to enter title of a feed"), text: $feed.name_)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        
                        Text("Shown in the tab bar")
                            .font(.footnote)
                            .foregroundColor(Color.secondary)
                    }
                }
                
                // TOGGLE REPLIES
                Toggle(isOn: Binding(get: {
                    feed.repliesEnabled
                }, set: { newValue in
                    feed.repliesEnabled = newValue
                })) {
                    Text("Show replies")
                }
                
                // CONTINUE WHERE LEFT OFF
                Toggle(isOn: Binding(get: {
                    feed.continue
                }, set: { newValue in
                    feed.continue = newValue
                })) {
                    Text("Resume where left")
                    Text("Catch up on missed posts since the last time you opened the feed")
                }
            }
            else {
                
                Section(header: Text("Feed settings", comment: "Header for entering title of a feed")) {
                    
                    // TOGLE PIN ON TAB BAR
                    Toggle(isOn: $feed.showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
                    
                    // TAB TITLE TEXTFIELD
                    if feed.showAsTab {
                        VStack(alignment: .leading) {
                            TextField(String(localized:"Tab title", comment:"Placeholder for input field to enter title of a feed"), text: $feed.name_)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            
                            Text("Shown in the tab bar")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                        }
                    }
                    
                    // TOGGLE REPLIES
                    Toggle(isOn: Binding(get: {
                        feed.repliesEnabled
                    }, set: { newValue in
                        feed.repliesEnabled = newValue
                    })) {
                        Text("Show replies")
                    }
                    
                    // CONTINUE WHERE LEFT OFF
                    Toggle(isOn: Binding(get: {
                        feed.continue
                    }, set: { newValue in
                        feed.continue = newValue
                    })) {
                        Text("Resume Where Left")
                        Text("Catch up on missed posts since the last time you opened the feed")
                    }
                }
                
                // SHARE LIST
                if !accounts.isEmpty { // Only show if we have full accounts
                    Section(header: Text("Share list", comment: "Header of Feed/List sharing settings")) {
                        
                        VStack(alignment: .leading) {
                            Toggle(isOn: $feed.sharedList, label: { Text("Make list public", comment: "Toggle to make list public")})
                                .disabled(!feed.sharedList && feed.contactPubkeys.isEmpty)
                            if feed.aTag != nil, let listNaddr = listNaddr {
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
                        
                        if feed.sharedList {
                            VStack(alignment: .leading) {
                                TextField(String(localized: "Title", comment:"Placeholder for input field to enter title of a shared list"), text: $feed.sharedTitle_)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .onAppear {
                                        if feed.sharedTitle_.isEmpty {
                                            feed.sharedTitle_ = feed.name_
                                        }
                                    }
                                Text("Share this list with a different title")
                                    .font(.footnote)
                                    .foregroundColor(Color.secondary)
                            }
                            
                            FullAccountPicker(selectedAccount: Binding(get: {
                                AccountsState.shared.fullAccounts.first(where: { $0.publicKey == feed.accountPubkey })
                            }, set: { selectedAccount in
                                feed.accountPubkey = selectedAccount?.publicKey
                            }), label: "Account")
                            .disabled(feed.aTag != nil)
                        }
                    }
                    .listRowBackground(theme.background)
                }
                
                // CONTACTS IN THIS LIST
                Section {
                    ForEach(listNRContacts) { nrContact in
                        NRContactSearchResultRow(nrContact: nrContact)
                            .padding()
                            .onTapGesture { navigateTo(NRContactPath(nrContact: nrContact), context: "Default") }
                            .listRowInsets(EdgeInsets())
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    feed.contactPubkeys.remove(nrContact.pubkey)
                                    listNRContacts.removeAll(where: { $0.pubkey == nrContact.pubkey })
                                    DataProvider.shared().save()
                                    sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: feed.subscriptionId, pubkeys: feed.contactPubkeys))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
    
                            }
                    }
                } header: {
                    Text("Contacts in list")
                }
                
                .onAppear {
                    accounts = AccountsState.shared.fullAccounts
                    
                    let feedContactPubkeys = feed.contactPubkeys
                    wasShared = feed.sharedList
                    let aTag = feed.aTag
                    bg().perform {
                        let listNRContacts: [NRContact] = Contact.fetchByPubkeys(feedContactPubkeys)
                            .map { NRContact.instance(of: $0.pubkey, contact: $0) }
                        
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
                    
                    if feed.sharedList,
                       let accountPubkey = feed.accountPubkey,
                       let fullAccount = AccountsState.shared.accounts.first(where: { $0.publicKey ==  accountPubkey })
                    {
                        publishList(feed, account: fullAccount)
                    }
                    else if let accountPubkey = feed.accountPubkey, feed.aTag != nil && !feed.sharedList && wasShared, let fullAccount = AccountsState.shared.accounts.first(where: { $0.publicKey ==  accountPubkey }) {
                        // No longer shared
                        
                        // set 0 p tags and send delete request
                        clearAndDeleteList(feed, account: fullAccount)
                    }
                }
            }
        }
        .toolbar { // .toolbar MUST be ON (NX)Form. Cannot use parent/NavigationLink Form, or in Section or SwifUI will duplicate buttons
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if isOwnList {
                    Button("Add contact", systemImage: "plus") {
                        addContactsSheetShown = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        
        
        .navigationTitle("Feed settings")
        .navigationBarTitleDisplayMode(.inline)
        
        .sheet(isPresented: $addContactsSheetShown) {
            NBNavigationStack {
                ContactsSearch(followingPubkeys: follows(),
                               prompt: "Search", onSelectContacts: { selectedContacts in
                    feed.contactPubkeys.formUnion(Set(selectedContacts.map { $0.pubkey }))
                    addContactsSheetShown = false
                    let feedContactPubkeys = feed.contactPubkeys
                    bg().perform {
                        let listNRContacts: [NRContact] = Contact.fetchByPubkeys(feedContactPubkeys)
                            .map { NRContact.instance(of: $0.pubkey, contact: $0) }
                        Task { @MainActor in
                            self.listNRContacts = listNRContacts
                        }
                    }
                    DataProvider.shared().save()
                    sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: feed.subscriptionId, pubkeys: feed.contactPubkeys))
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
                .environment(\.theme, theme)
                .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadCloudFeeds() }) {
        if let feed = PreviewFetcher.fetchCloudFeed(type: "pubkeys") {
            FeedSettings(feed: feed)
        }
    }
}


// Helpers

func publishList(_ feed: CloudFeed, account: CloudAccount) {
    var nEvent = NEvent(content: "")
    // Share as .followPack if unknown
    // else share as whatever it was before (.followPack or .followSet)
    
    let listKind: (nEventKind: NEventKind, kind: Int64) = (feed.aTag?.kind ?? 39089) == 39089 ? (.followPack, 39089) : (.followSet, 30000)
    
    nEvent.kind = listKind.nEventKind
    nEvent.publicKey = account.publicKey
    nEvent.createdAt = NTimestamp.init(date: Date())
    nEvent.tags.append(NostrTag(["title", feed.sharedTitle_]))
    
    // Keep linked to existing aTag / listId
    if let aTag = feed.aTag, aTag.pubkey == account.publicKey {
        nEvent.tags.append(NostrTag(["d", aTag.definition]))
    }
    else { // First time, create new aTag and store in listId to keep CloudFeed linked to kind:39089 nostr list
        // Brand new onces should be kind 39089, no longer kind 30000
        let aTag = ATag(kind: 39089, pubkey: account.publicKey, definition: feed.id?.uuidString ?? UUID().uuidString)
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
    
    let listKind: (nEventKind: NEventKind, kind: Int64) = (feed.aTag?.kind ?? 39089) == 39089 ? (.followPack, 39089) : (.followSet, 30000)
    
    nEvent.kind = listKind.nEventKind
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
    deleteReq.tags.append(NostrTag(["k", "\(listKind.kind.description)"]))
    
    
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
            let deletedById = signedDeleteEvent.id
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
                    wipedEvent.deletedById = deletedById
                    let wipedEventId = wipedEvent.id
                    DataProvider.shared().bgSave()
                    Task { @MainActor in
                        ViewUpdates.shared.postDeleted.send((toDeleteId: wipedEventId, deletedById: deletedById))
                    }
                }
                Unpublisher.shared.publishNow(signedWipedEvent) // is published before delete req (Now)
            }
            
        }
    }
    
}
