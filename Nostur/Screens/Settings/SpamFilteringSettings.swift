//
//  SpamFilteringSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import NavigationBackport

struct SpamFilteringSettings: View {
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var wot = WebOfTrust.shared
    @AppStorage("wotDunbarNumber") private var wotDunbarNumber: Int = 1000
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    
    @State private var notInWoTcount = 0
    @State private var notInWoTLastHours = 0
    
    var body: some View {
        NXForm {
            Section(header: Text("Spam filtering", comment:"Setting heading on settings screen")) {
                VStack(alignment: .leading) {
                    WebOfTrustLevelPicker()
                    
                    Text("Filter by your follows only (strict), or also your follows follows (normal)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    MainWoTaccountPicker()
                        .frame(maxHeight: 20)
                        .padding(.top, 5)
                    
                    if #available(iOS 16.0, *) {
                        Text("To log in with other accounts, but keep filtering using the main Web of Trust account")
                            .lineLimit(2, reservesSpace: true)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    else {
                        Text("To log in with other accounts, but keep filtering using the main Web of Trust account")
                            .lineLimit(2)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                
                if (settings.webOfTrustLevel == SettingsStore.WebOfTrustLevel.normal.rawValue) {
                    VStack(alignment: .leading) {
                        Text("Nostr Dunbar Number")
                        Picker("Dunbar number", selection: $wotDunbarNumber) {
                            Text("250").tag(250)
                            Text("500").tag(500)
                            Text("1000").tag(1000)
                            Text("2000").tag(2000)
                            Text("♾️").tag(0)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        Text("Follow lists with a size higher than this threshold will be considered low quality and not included in your Web of Trust")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .onChange(of: wotDunbarNumber) { newValue in
                        bg().perform {
                            guard let account = account() else { return }
                            let wotFollowingPubkeys = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys) // We don't include silent follows in WoT
                            wot.localReload(wotFollowingPubkeys: wotFollowingPubkeys)
                        }
                    }
                }
                
                HStack {
                    Text("Last updated: \(wot.lastUpdated?.formatted() ?? "Never")", comment: "Last updated date of WoT in Settings")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .onAppear {
                            bg().perform {
                                wot.loadLastUpdatedDate()
                            }
                            if mainAccountWoTpubkey == "" {
                                wot.guessMainAccount()
                            }
                        }
                    Spacer()
                    if wot.updatingWoT {
                        ProgressView()
                    }
                    else if mainAccountWoTpubkey != "" {
                        Button(String(localized:"Update", comment:"Button to update WoT")) {
                            guard !wot.updatingWoT else { return }
                            wot.updatingWoT = true
                            wot.loadWoT(force: true)
                        }
                    }
                }
                
                Group {
                    if wot.allowedKeysCount == 0 || settings.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                        Text("Currently allowed by the filter: Everyone")
                    }
                    else {
                        Text("Currently allowed by the filter: \(wot.allowedKeysCount) contacts")
                            .onAppear {
                                bg().perform {
                                    if ConnectionPool.shared.notInWoTcount > 0 {
                                        let notInWoTsince = ConnectionPool.shared.notInWoTsince
                                        let notInWoTcount = ConnectionPool.shared.notInWoTcount
                                        
                                        let lastHours: Int = {
                                            let calendar = Calendar.current
                                            let components = calendar.dateComponents([.hour], from: notInWoTsince, to: Date())
                                            return components.hour ?? 0
                                        }()
                                        
                                        Task { @MainActor in
                                            self.notInWoTcount = notInWoTcount
                                            self.notInWoTLastHours = lastHours
                                        }
                                    }
                                }
                            }
                        
                        if notInWoTcount != 0 {
                            Text("Spam filtered in the last \(notInWoTLastHours > 1 ? "\(notInWoTLastHours) hours" : "hour"): \(notInWoTcount) items")
                        }
                    }
                }.font(.caption).foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading) {
                AutodownloadLevelPicker()
                
                Text("When to auto-download media posted by others")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Message verification", comment: "Setting heading on settings screen")) {
                Toggle(isOn: $settings.isSignatureVerificationEnabled) {
                    VStack(alignment: .leading) {
                        Text("Verify message signatures", comment: "Setting on settings screen")
                        Text("Turn off to save battery life and trust the relays for the authenticity of messages", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
//            .listRowBackground(theme.background)
        }
    }
}

#Preview {
    NBNavigationStack {
        SpamFilteringSettings()
    }
}
