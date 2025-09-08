//
//  RelayFeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2025.
//

import SwiftUI

struct RelayFeedSettings: View {
    @ObservedObject public var feed: CloudFeed
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        NXForm {
            Section(header: Text("Feed settings", comment: "Header for feed settings")) {
                
                // PIN ON TAB BAR
                Toggle(isOn: $feed.showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
                
                // TAB TITLE
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
                
                // SHOW REPLIES
                Toggle(isOn: Binding(get: {
                    feed.repliesEnabled
                }, set: { newValue in
                    feed.repliesEnabled = newValue
                })) {
                    Text("Show replies")
                }
                
                // WEB OF TRUST SPAMFILTER
                Toggle(isOn: Binding(get: {
                    feed.wotEnabled
                }, set: { newValue in
                    feed.wotEnabled = newValue
                })) {
                    Text("Web of Trust spam filter")
                    Text("Only show content from your follows or follows-follows")
                }
            }
            
            Section {
                FullAccountPicker(selectedAccount: Binding(get: {
                    AccountsState.shared.fullAccounts.first(where: { $0.publicKey == feed.accountPubkey })
                }, set: { selectedAccount in
                    feed.accountPubkey = selectedAccount?.publicKey
                }), label: "Authenticate as")
                
                NavigationLink(destination: FeedRelaysPicker(selectedRelays: $feed.relays_)) {
                    Text("Select relay(s)")
                }
                
            } header: {
                Text("Relay feed")
            }
        }
        
        .navigationTitle("Feed settings")
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    DataProvider.shared().save()
                    sendNotification(.listRelaysChanged, NewRelaysForList(subscriptionId: feed.subscriptionId, relays: feed.relaysData, wotEnabled: feed.wotEnabled))
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadCloudFeeds() }) {
        if let feed = PreviewFetcher.fetchCloudFeed(type: CloudFeedType.relays.rawValue) {
            FeedSettings(feed: feed)
        }
    }
}
