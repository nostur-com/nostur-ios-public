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

    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        switch feed.type {
        case "following":
            FollowingFeedSettings(feed: feed)
            
        case "picture":
            PictureFeedSettings(feed: feed)
            
        case "relays":
            RelayFeedSettings(feed: feed)
            
        case "pubkeys", nil, "30000", "39089":
            ContactFeedSettings(feed: feed)

        default:
            Rectangle()
                .frame(width: 100, height: 100)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close", systemImage: "xmark") {
                          dismiss()
                        }
                    }
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
                if let feed = PreviewFetcher.fetchCloudFeed() {
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
