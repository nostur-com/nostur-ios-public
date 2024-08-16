//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var feed: CloudFeed
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Form {
            if #available(iOS 16, *) {
                Section("App theme") {
                    AppThemeSwitcher()
                }
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
                
                if feed.accountPubkey != nil, !la.account.followingHashtags.isEmpty {
                    Section("Included hashtags") {
                        FeedSettings_Hashtags(hashtags: Array(la.account.followingHashtags), onChange: { hashtags in
                            la.account.followingHashtags = Set(hashtags)
//                            needsReload = true
                            la.account.publishNewContactList()
                        })
                    }
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
            }
            
            if feed.type == "pubkeys" || feed.type == nil {
                Section("") {
                    Toggle(isOn: Binding(get: {
                        feed.repliesEnabled
                    }, set: { newValue in
                        feed.repliesEnabled = newValue
                    })) {
                        Text("Show replies")
                    }
                    
                    NavigationLink(destination: EditNosturList(list: feed)) {
                        Text("Configure contacts...")
                    }
                }
            }
        }
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

