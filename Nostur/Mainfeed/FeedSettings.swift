//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var lvm:LVM
    public var list:CloudFeed? = nil
    
    @EnvironmentObject private var la:LoggedInAccount
    
    @State private var needsReload = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Form {
            Section("App theme") {
                AppThemeSwitcher()
            }
            
            Section("") {
                Toggle(isOn: $lvm.hideReplies.not) {
                    Text("Show replies")
                }
                if lvm.type == .relays {
                    Toggle(isOn: $lvm.wotEnabled) {
                        Text("Web of Trust filter")
                    }
                }
                Group {
                    if let list = list, lvm.type == .relays {
                        NavigationLink(destination: EditRelaysNosturList(list: list)) {
                            Text("Configure relays...")
                        }
//                        NavigationLink("Configure relays...", value: list)
//                        Button("Configure relays...") {
//                            guard let list = list else { return }
//                            navigateToOnMain(list)
//                        }
                    }
                    else if let list = list, lvm.pubkey == nil && lvm.id != "Explore" {
                        NavigationLink(destination: EditNosturList(list: list)) {
                            Text("Configure contacts...")
                        }
//                        NavigationLink("Configure contacts...", value: list)
//                        Button("Configure contacts...") {
//                            guard let list = list else { return }
//                            navigateToOnMain(list)
//                        }
                    }
                }
            }
            
            if lvm.pubkey != nil, !la.account.followingHashtags.isEmpty {
                Section("Included hashtags") {
                    FeedSettings_Hashtags(hashtags: Array(la.account.followingHashtags), onChange: { hashtags in
                        la.account.followingHashtags = Set(hashtags)
                        needsReload = true
                        la.account.publishNewContactList()
                    })
                } 
            }
            if lvm.pubkey == nil, let list = list, !list.followingHashtags.isEmpty {
                Section("Included hashtags") {
                    FeedSettings_Hashtags(hashtags: Array(list.followingHashtags), onChange: { hashtags in
                        list.followingHashtags = Set(hashtags)
                        needsReload = true
                    })
                }
            }
        }
        .onChange(of: lvm.wotEnabled) { wotEnabled in
            guard let list = list else { return }
            list.wotEnabled = wotEnabled
        }
        .onDisappear {
            if needsReload {
                lvm.reload()
            }
        }
        .navigationTitle("\(lvm.pubkey != nil ? String(localized: "Following") : lvm.name) settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct FeedSettingsTester: View {
    @EnvironmentObject private var la:LoggedInAccount
    
    var body: some View {
        NavigationStack {
            VStack {
                FeedSettings(lvm:LVMManager.shared.followingLVM(forAccount: la.account))
                if let list = PreviewFetcher.fetchList() {
                    FeedSettings(lvm:LVMManager.shared.listLVM(forList: list))
                }
                Spacer()
            }
        }
        .onAppear {
            la.account.followingHashtags = ["bitcoin","nostr"]
            Themes.default.loadPurple()
        }
    }
}


struct FeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadNosturLists() }) {
            FeedSettingsTester()
        }
    }
}

