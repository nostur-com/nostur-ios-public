//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var feed: CloudFeed
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Form {
            if #available(iOS 16, *), feed.type != "30000" && feed.listId == nil {
                Section("App theme") {
                    AppThemeSwitcher()
                }
                .listRowBackground(themes.theme.background)
            }
            
            if let aTagString = feed.listId, let aTag = try? ATag(aTagString) {
                // Even if we change from 30000 to own pubkeys sheet, still show where the list came from, also makes easy to toggle on off subscribe updates again.
            
                // Feed managed by
                // Updates by author automatic blabla
                // TODO: show original name (if tab name changed)
                Section {
                
                    ListManagedByView(feed: feed, aTag: aTag)
                        .padding(.vertical, 10)
                    
//                    HStack {
//                        VStack(alignment: .leading) {
//                            Spacer()
//                            ListManagedByView(feed: feed, aTag: aTag)
//                            Spacer()
//                        }
//                        Spacer()
//                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal, 20)
                    .listRowBackground(themes.theme.background)
                }
                
                // Zap author
                
                Section {
                    // Copy to own feed. No longer managed
                    Toggle(isOn: Binding(get: {
                        feed.type == "30000"
                    }, set: { newValue in
                        if newValue {
                            feed.type = "30000"
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
                .listRowBackground(themes.theme.background)
            }
            
            
            if feed.type == "following" {
                Section("") {
                    Toggle(isOn: Binding(get: {
                        feed.repliesEnabled
                    }, set: { newValue in
                        feed.repliesEnabled = newValue
                    })) {
                        Text("Show replies")
                    }
                }
                .listRowBackground(themes.theme.background)
                
                if feed.accountPubkey != nil, !la.account.followingHashtags.isEmpty {
                    Section("Included hashtags") {
                        FeedSettings_Hashtags(hashtags: Array(la.account.followingHashtags), onChange: { hashtags in
                            la.account.followingHashtags = Set(hashtags)
//                            needsReload = true
                            la.account.publishNewContactList()
                        })
                    }
                    .listRowBackground(themes.theme.background)
                }
            }
            
            if feed.type == "relays" {
                Section("") {
                    Toggle(isOn: Binding(get: {
                        feed.repliesEnabled
                    }, set: { newValue in
                        feed.repliesEnabled = newValue
                    })) {
                        Text("Show replies")
                    }
                    Toggle(isOn: Binding(get: {
                        feed.wotEnabled
                    }, set: { newValue in
                        feed.wotEnabled = newValue
                    })) {
                        Text("Web of Trust filter")
                    }
                    NavigationLink(destination: EditRelaysNosturList(list: feed)) {
                        Text("Configure relays...")
                    }
                }
                .listRowBackground(themes.theme.background)
            }
            
            if (feed.type == "pubkeys" || feed.type == nil) || feed.type == "30000"  {
                Section("") {
                    Toggle(isOn: Binding(get: {
                        feed.repliesEnabled
                    }, set: { newValue in
                        feed.repliesEnabled = newValue
                    })) {
                        Text("Show replies")
                    }
                    
                    if feed.type != "30000" { // no kind:30000, these are managed by other author
                        NavigationLink(destination: EditNosturList(list: feed)) {
                            Text("Configure contacts...")
                        }
                    }
                }
                .listRowBackground(themes.theme.background)
            }
        }
        .scrollContentBackgroundHidden()
        .navigationTitle("Feed settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
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
    
    var body: some View {
        SendSatsToSupportView(pfpAttributes: PFPAttributes(pubkey: aTag.pubkey), listName: feed.name)
    }
}


struct SendSatsToSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var pfpAttributes: PFPAttributes
    @ObservedObject public var ss: SettingsStore = .shared
    public var listName: String?
    
    var body: some View {
        VStack(alignment: .leading) {
            if let listName {
                Text(listName)
                    .font(.title)
            }
            HStack {
                Text("Maintained by ")
                PFPandName(pfpAttributes: pfpAttributes, dismissOnNavigate: true)
            }
            
            if  ss.nwcReady { // TODO: FIX FOR NON NWC
                if let nrContact = pfpAttributes.contact {
                    ProfileZapButton(contact: nrContact) // TODO: Support zapATag
                }
                
                // feed is based on a list of people managed by ....
                // zap to support people who curate high quality lists
                
                Text("Support people who curate high quality lists by zapping them")
                    .font(.footnote)
            }
            
        }
        .navigationTitle("\(listName ?? "List") by \(pfpAttributes.anyName)")
    }
}




// TODO: Should start reusing this everywhere? add flags and toggles for size / layout / position etc / in sheet or not (for dismiss)
struct PFPandName: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var pfpAttributes: PFPAttributes
    
    public var dismissOnNavigate: Bool = false
    
    var body: some View {
        HStack {
            ObservedPFP(pfp: pfpAttributes, size: 20.0)
                .onTapGesture(perform: navigateToContact)
            Text(pfpAttributes.anyName)
        }
//        .navigationTitle("List by \(pfpAttributes.anyName)")
        .onAppear {
            bg().perform {
                if pfpAttributes.contact == nil || pfpAttributes.contact?.metadata_created_at == 0 {
                    QueuedFetcher.shared.enqueue(pTag: pfpAttributes.pubkey)
                }
            }
        }
        .onDisappear {
            bg().perform {
                if pfpAttributes.contact == nil || pfpAttributes.contact?.metadata_created_at == 0 {
                    QueuedFetcher.shared.dequeue(pTag: pfpAttributes.pubkey)
                }
            }
        }
    }
    
    private func navigateToContact() {
        if dismissOnNavigate {
            dismiss()
            AppSheetsModel.shared.dismiss()
        }
        if let nrContact = pfpAttributes.contact {
            navigateTo(nrContact)
        }
        else {
            navigateTo(ContactPath(key: pfpAttributes.pubkey))
        }
    }
}
