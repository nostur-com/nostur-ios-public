//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    @ObservedObject public var lvm:LVM
    @Binding public var showFeedSettings:Bool
    public var list:CloudFeed? = nil
    
    @EnvironmentObject private var la:LoggedInAccount
    
    @State private var needsReload = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Rectangle().fill(.thinMaterial)
            .ignoresSafeArea()
            .onTapGesture {
                showFeedSettings = false
            }
            .overlay(alignment: .top) {
                Box {
                    VStack(alignment: .leading) {
                        AppThemeSwitcher(showFeedSettings: $showFeedSettings)
                        .padding(.bottom, 15)
                        Text("Settings for \(lvm.pubkey != nil ? String(localized: "Following") : lvm.name)")
                            .fontWeight(.bold)
                            .hCentered()
                        Toggle(isOn: $lvm.hideReplies.not) {
                            Text("Show replies")
                        }
                        if lvm.type == .relays {
                            Toggle(isOn: $lvm.wotEnabled) {
                                Text("Web of Trust filter")
                            }
                        }
                        Group {
                            if lvm.type == .relays {
                                Button("Configure relays...") {
                                    guard let list = list else { return }
                                    navigateToOnMain(list)
                                }
                            }
                            else if lvm.pubkey == nil && lvm.id != "Explore" {
                                Button("Configure contacts...") {
                                    guard let list = list else { return }
                                    navigateToOnMain(list)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                        
                        if lvm.pubkey != nil, !la.account.followingHashtags.isEmpty {
                           
                            Text("Included hashtags:")
                                .padding(.top, 20)
                            FeedSettings_Hashtags(hashtags: Array(la.account.followingHashtags), onChange: { hashtags in
                                la.account.followingHashtags = Set(hashtags)
                                needsReload = true
                                la.account.publishNewContactList()
                            })
                            .frame(height: 375)
                        }
                        if lvm.pubkey == nil, let list = list, !list.followingHashtags.isEmpty {
                            
                            Text("Included hashtags:")
                                .padding(.top, 20)
                            FeedSettings_Hashtags(hashtags: Array(list.followingHashtags), onChange: { hashtags in
                                list.followingHashtags = Set(hashtags)
                                needsReload = true
                            })
                            .frame(height: 375)
                        }
                    }
                }
                .padding(20)
                .ignoresSafeArea()
                .offset(y: 1.0)
            }
            .onReceive(receiveNotification(.showFeedToggles)) { _ in
                if showFeedSettings {
                    showFeedSettings = false
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
    }
}

struct FeedSettingsTester: View {
    @EnvironmentObject private var la:LoggedInAccount
    
    var body: some View {
        NavigationStack {
            VStack {
                FeedSettings(lvm:LVMManager.shared.followingLVM(forAccount: la.account), showFeedSettings: .constant(true))
                if let list = PreviewFetcher.fetchList() {
                    FeedSettings(lvm:LVMManager.shared.listLVM(forList: list), showFeedSettings: .constant(true))
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

