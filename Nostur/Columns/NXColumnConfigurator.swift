//
//  NXColumnConfigurator.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/10/2024.
//

import SwiftUI



struct NXColumnConfigurator: View {
    @Environment(\.theme) private var theme
    @State private var cloudFeed: CloudFeed?
    @State private var columnConfig: NXColumnConfig?
    
    @State private var columnType: String = "Following"
    @State private var accountPubkey: String?
    @State private var account: CloudAccount?
    @State private var wotEnabled: Bool = false
    @State private var repliesEnabled: Bool = false
    @State private var title: String = ""
    
    private var accounts: [CloudAccount] { AccountsState.shared.accounts.filter { $0.publicKey != GUEST_ACCOUNT_PUBKEY } }
    
    private var formIsValid: Bool {
        if columnType == "Following" && account != nil { return true }
        if columnType == "Mentions" && account != nil { return true }
        if columnType == "Contacts" { return true }
        if columnType == "Relays" { return true }
        if columnType == "Hashtags" { return true }
        return false
    }
    
    var body: some View {
        
        Form {
            
            Picker("Type", selection: $columnType) {
                Text("Following").tag("Following")
                Text("Contacts").tag("Contacts")
                Text("Relays").tag("Relays")
                Text("Mentions").tag("Mentions")
                Text("Hashtags").tag("Hashtags")
            }
        
            if columnType == "Following" || columnType == "Mentions" {
                Picker(selection: $accountPubkey) {
                    ForEach(accounts) { account in
                        HStack {
                            PFP(pubkey: account.publicKey, account: account, size: 20.0)
                            Text(account.anyName)
                        }
                        .tag(account.publicKey)
                        .foregroundColor(theme.primary)
                    }
                    
                } label: {
                    Text("Account")
                }
                .pickerStyleCompatNavigationLink()
            }
            
            if columnType == "Relays" || columnType == "Hashtags" {
                Toggle("Enable WoT filter", isOn: $wotEnabled)
            }
            
            if columnType == "Following" || columnType == "Contacts" || columnType == "Relays" || columnType == "Hashtags" {
                Toggle("Show replies", isOn: $repliesEnabled)
            }
        }
        
        .navigationTitle("Configure column")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: accountPubkey) { pubkey in
            account = accounts.first(where: { $0.publicKey == pubkey })
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    guard formIsValid else { return }
                    saveColumn()
                }
                .buttonStyleGlassProminent()
                .disabled(!formIsValid)
            }
        }
    }
    
    
    private func saveColumn() {
        // Create CloudFeed if it doesn't exist yet
        if cloudFeed == nil {
            let context = viewContext()
            // Create new following feed
            let newCloudFeed = CloudFeed(context: context)
            newCloudFeed.wotEnabled = wotEnabled
            newCloudFeed.repliesEnabled = repliesEnabled
            newCloudFeed.name = "\(columnType) feed"
            newCloudFeed.showAsTab = false // or it will appear in "List" / "Custom Feeds"
            newCloudFeed.id = UUID()
            newCloudFeed.createdAt = .now
            newCloudFeed.order = 0
            
            newCloudFeed.accountPubkey = if columnType == "Following" || columnType == "Mentions" {
                accountPubkey
            }
            else { nil }
            
            newCloudFeed.type = switch columnType {
            case "Following":
                CloudFeedType.following.rawValue
            case "Contacts":
                CloudFeedType.pubkeys.rawValue
            case "Relays":
                CloudFeedType.relays.rawValue
            case "Mentions":
                CloudFeedType.mentions.rawValue
            case "Hashtags":
                CloudFeedType.hashtags.rawValue
            default:
                nil
            }
            
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
        
        // Create NXColumnConfig
    }
    
    private func updateColumnConfig() {
//        // Account based
//        if let account = accounts.first(where: { $0.publicKey == accountPubkey }) {
//
//            let columnType: NXColumnType = switch columnType {
//            case "Following":
//                .following(getFollowingFeed(account.publicKey, accountName: account.anyName))
//            case "Contacts":
//                .pubkeys(<#T##CloudFeed#>)
//            case "Relays":
//                .relays(<#T##CloudFeed#>)
//            case "Mentions":
//                .mentions
//            case "Hashtags":
//                .hashtags(<#T##CloudFeed#>)
//
//            columnConfig = NXColumnConfig(
//                id: columnConfig?.id ?? UUID().uuidString,
//                columnType: columnType
//                },
//                accountPubkey: accountPubkey,
//                name: "",
//                pubkeys: <#T##Set<String>#>,
//                hashtags: <#T##Set<String>#>
//            )
//        }
//
//        else { // Not account based
//
//
//
//        }
        
    }
}

import NavigationBackport

#Preview {
    PreviewContainer({ pe in pe.loadAccounts() }) {
        NBNavigationStack {
            NXColumnConfigurator()
        }
    }
}


private func getFollowingFeed(_ accountPubkey: String, accountName: String? = nil) -> CloudFeed {
    // Repair first (remove duplicates, keep latest)
    let context = viewContext()
    let fr = CloudFeed.fetchRequest()
    fr.predicate = NSPredicate(format: "type = %@ AND accountPubkey = %@", CloudFeedType.following.rawValue, accountPubkey)
    
    let followingFeeds: [CloudFeed] = (try? context.fetch(fr)) ?? []
    let followingFeedsNewest: [CloudFeed] = followingFeeds
        .sorted(by: { a, b in
            let mostRecentA = max(a.createdAt ?? .now, a.refreshedAt ?? .now)
            let mostRecentB = max(b.createdAt ?? .now, b.refreshedAt ?? .now)
            return mostRecentA > mostRecentB
        })
    
    if let followingFeed = followingFeedsNewest.first {
        // Remove duplicates
        for f in followingFeedsNewest.dropFirst(1) {
            context.delete(f)
        }
        DataProvider.shared().saveToDiskNow(.viewContext)
        // Return most recent existing
        return followingFeed
    }
    else {
        // Create new following feed
        let newFollowingFeed = CloudFeed(context: context)
        newFollowingFeed.wotEnabled = false // WoT is only for hashtags or relays feeds
        newFollowingFeed.name = "Following for " + (accountName ?? accountPubkey)
        newFollowingFeed.showAsTab = false // or it will appear in "List" / "Custom Feeds"
        newFollowingFeed.id = UUID()
        newFollowingFeed.createdAt = .now
        newFollowingFeed.accountPubkey = accountPubkey
        newFollowingFeed.type = CloudFeedType.following.rawValue
        newFollowingFeed.order = 0
        
        // Resume Where Left: Default on for contact-based. Default off for relay-based
        newFollowingFeed.continue = true
        
        DataProvider.shared().saveToDiskNow(.viewContext)
        
        return newFollowingFeed
    }
}
