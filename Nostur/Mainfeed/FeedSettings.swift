//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var feed: CloudFeed
    @EnvironmentObject private var la: LoggedInAccount
    
    private var isOwnManagedList: Bool {
        feed.accountPubkey != nil && (feed.type == "pubkeys" || feed.type == nil) && feed.listId != nil
    }
    
    @State private var authenticationAccount: CloudAccount?
    
    var body: some View {

#if DEBUG
        let _ = Self._printChanges()
#endif
        Group {
            switch feed.type {
            case "following":
                NXForm {
                    
                    feedSettingsSection
                    
                    if feed.accountPubkey != nil, !la.account.followingHashtags.isEmpty {
                        Section("Included hashtags") {
                            FeedSettings_Hashtags(hashtags: Array(la.account.followingHashtags), onChange: { hashtags in
                                la.account.followingHashtags = Set(hashtags)
                                la.account.publishNewContactList()
                            })
                        }
                        .listRowBackground(theme.background)
                    }
                }
                
            case "relays":
                NXForm {
                    feedSettingsSection
                    
                    Section {
                        FullAccountPicker(selectedAccount: $authenticationAccount, label: "Authenticate as")
                            .onAppear {
                                if let feedAccountPubkey = feed.accountPubkey {
                                    authenticationAccount = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == feedAccountPubkey })
                                }
                            }
                        NavigationLink(destination: EditRelaysNosturList(list: feed)) {
                            Text("Configure relays...")
                        }
                    } header: {
                        Text("Relay feed")
                    }
                }
            
            case "pubkeys", nil, "30000", "39089":
                // Managed by someone else, with toggle subscribe on/off (switchs between "pubkeys" and "30000"/"39089")
                if !isOwnManagedList, let aTagString = feed.listId, let aTag = try? ATag(aTagString) {
                    NXForm {
                        feedSettingsSection
                        
                        // Even if we change from 30000 to own pubkeys sheet, still show where the list came from, also makes easy to toggle on off subscribe updates again.
                    
                        // Feed managed by... zap author...
                        Section {
                            ListManagedByView(feed: feed, aTag: aTag, parentDismiss: dismiss)
                                .padding(.vertical, 10)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal, 20)
                        }
                        .listRowBackground(theme.background)
                        
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
                        .listRowBackground(theme.background)
                    }
                }
                else {
                    EditNosturList(list: feed)
                }

            default:
                NXForm {
                    if #available(iOS 16, *) {
                       Section("App theme") {
                           AppThemeSwitcher()
                       }
                       .listRowBackground(theme.background)
                   }
                }
            }
        }
        .scrollContentBackgroundHidden()
        .navigationTitle("Feed settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    
                    dismiss()
                }
            }
        }
    }
    
    
    @ViewBuilder
    private var feedSettingsSection: some View {
        Section(header: Text("Feed settings", comment: "Header for entering title of a feed")) {
            Group {
                if feed.accountPubkey != la.pubkey { // Don't show if it is our own main following feed
                    Toggle(isOn: $feed.showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
                }
                
                if feed.showAsTab {
                    VStack(alignment: .leading) {
                        TextField(String(localized:"Tab title", comment:"Placeholder for input field to enter title of a feed"), text: $feed.name_)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        
                        if feed.type != "relays" {
                            Text("Shown in the tab bar (not public)")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
                
                Toggle(isOn: Binding(get: {
                    feed.repliesEnabled
                }, set: { newValue in
                    feed.repliesEnabled = newValue
                })) {
                    Text("Show replies")
                }
                
                if feed.type == "relays" {
                    Toggle(isOn: Binding(get: {
                        feed.wotEnabled
                    }, set: { newValue in
                        feed.wotEnabled = newValue
                    })) {
                        Text("Web of Trust filter")
                    }
                }
            }
            .listRowBackground(theme.background)
        }
    }
}

import NavigationBackport

struct FeedSettingsTester: View {
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        NBNavigationStack {
            VStack {
                if let feed = PreviewFetcher.fetchList() {
                    FeedSettings(feed: feed)
                        .environmentObject(Themes.default)
                }
                Spacer()
            }
        }
        .nbUseNavigationStack(.never)
        .onAppear {
            la.account.followingHashtags = ["bitcoin","nostr"]
            Themes.default.loadPurple()
        }
    }
}


struct FeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadCloudFeeds() }) {
            FeedSettingsTester()
        }
    }
}



struct ListManagedByView: View {
    @ObservedObject var feed: CloudFeed
    public let aTag: ATag
    let parentDismiss: DismissAction
    
    var body: some View {
        SendSatsToSupportView(pubkey: aTag.pubkey, listName: feed.name, parentDismiss: parentDismiss)
    }
}


struct SendSatsToSupportView: View {
    private var pubkey: String
    @ObservedObject private var nrContact: NRContact
    @ObservedObject private var ss: SettingsStore = .shared
    private var listName: String?
    let parentDismiss: DismissAction
    
    init(pubkey: String, listName: String? = nil, parentDismiss: DismissAction) {
        self.pubkey = pubkey
        nrContact = NRContact.instance(of: pubkey)
        self.listName = listName
        self.parentDismiss = parentDismiss
    }
    
    
    var body: some View {
        VStack(alignment: .leading) {
            if let listName {
                Text(listName)
                    .font(.title2)
            }
            HStack {
                Text("Maintained by ")
                PFPandName(nrContact: nrContact)
                    .onTapGesture {
                        navigateToContact(pubkey: nrContact.pubkey,  context: "Default")
                        parentDismiss()
                    }
            }
            
            if  ss.nwcReady { // TODO: FIX FOR NON NWC
                ProfileZapButton(nrContact: nrContact) // TODO: Support zapATag
                
                // feed is based on a list of people managed by ....
                // zap to support people who curate high quality lists
                
                Text("Support people who curate high quality lists by zapping them")
                    .font(.footnote)
            }
            
        }
        .navigationTitle("\(listName ?? "List") by \(nrContact.anyName)")
    }
}
