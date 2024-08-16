//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    public var config: NXColumnConfig
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
            
            
            if case .following(let feed) = config.columnType {
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
            
            if case .relays(let feed) = config.columnType {
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
            
            if case .pubkeys(let feed) = config.columnType {
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
//        .onChange(of: lvm.wotEnabled) { wotEnabled in
//            guard let list = list else { return }
//            list.wotEnabled = wotEnabled
//        }
//        .onDisappear {
//            if needsReload {
//                lvm.reload()
//            }
//        }
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
                if let list = PreviewFetcher.fetchList() {
                    let config = NXColumnConfig(id: list.id?.uuidString ?? "?", columnType: .pubkeys(list), accountPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", name: "Following")
                    FeedSettings(config: config)
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

