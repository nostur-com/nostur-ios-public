//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

struct FeedSettings: View {
    
    @ObservedObject var lvm:LVM
    @Binding var showFeedSettings:Bool
    var list:NosturList? = nil
    @State var needsReload = false
    
    var body: some View {
        Rectangle().fill(.thinMaterial)
            .ignoresSafeArea()
            .onTapGesture {
                showFeedSettings = false
            }
            .overlay(alignment: .top) {
                VStack(alignment: .leading) {
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
                    
                    if lvm.pubkey != nil, let account = NosturState.shared.account, !account.followingHashtags.isEmpty {
                       
                        Text("Included hashtags:")
                            .padding(.top, 20)
                        FeedSettings_Hashtags(hashtags: Array(account.followingHashtags), onChange: { hashtags in
                            guard let account = NosturState.shared.account else { return }
                            account.followingHashtags = Set(hashtags)
                            needsReload = true
                            NosturState.shared.publishNewContactList()
                        })
                        .frame(height: 200)
                    }
                    if lvm.pubkey == nil, let list = list, !list.followingHashtags.isEmpty {
                        
                        Text("Included hashtags:")
                            .padding(.top, 20)
                        FeedSettings_Hashtags(hashtags: Array(list.followingHashtags), onChange: { hashtags in
                            list.followingHashtags = Set(hashtags)
                            needsReload = true
                        })
                        .frame(height: 200)
                    }
                }
                .padding(10)
                .roundedBoxShadow()
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
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        if let account = ns.account {
            NavigationStack {
                VStack {
                    FeedSettings(lvm:LVMManager.shared.followingLVM(forAccount: account), showFeedSettings: .constant(true))
                    if let list = PreviewFetcher.fetchList() {
                        FeedSettings(lvm:LVMManager.shared.listLVM(forList: list), showFeedSettings: .constant(true))
                    }
                    Spacer()
                }
            }
            .onAppear {
                account.followingHashtags = ["bitcoin","nostr"]
            }
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

