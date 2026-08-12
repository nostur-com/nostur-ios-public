//
//  FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI
import CoreData

@MainActor
final class FeedSettingsDraft: ObservableObject {
    let feed: CloudFeed
    private let originalValues: [String: Any]
    private let originalMediaSource: MediaFeedSource
    private let originalFollowingHashtags: Set<String>
    private var didFinish = false

    @Published var mediaSource: MediaFeedSource
    @Published var mediaRelays: Set<CloudRelay>
    @Published var vineAutoplayAudio: Bool
    @Published var followingHashtags: Set<String>

    init(feed: CloudFeed) {
        self.feed = feed
        self.originalValues = feed.dictionaryWithValues(forKeys: Array(feed.entity.attributesByName.keys))
        self.originalMediaSource = feed.mediaFeedSource
        self.originalFollowingHashtags = feed.account?.followingHashtags ?? []
        self.mediaSource = feed.mediaFeedSource
        self.mediaRelays = feed.relays_
        self.vineAutoplayAudio = UserDefaults.standard.object(forKey: "vine_autoplay_audio_enabled") as? Bool ?? true
        self.followingHashtags = feed.account?.followingHashtags ?? []
    }

    var selectedRelayCount: Int { mediaRelays.count }

    func apply() {
        guard !didFinish else { return }
        didFinish = true

        let relayURLs = mediaRelays.compactMap(\.url_).joined(separator: " ")
        let relaysChanged = feed.relays != relayURLs
        feed.relays = relayURLs
        if selectedRelayCount == 0 && mediaSource == .selectedRelays {
            mediaSource = .follows
        }

        let sourceChanged = feed.mediaFeedSource != mediaSource
        if sourceChanged {
            feed.mediaFeedSource = mediaSource
        }
        if relaysChanged && !sourceChanged {
            feed.mediaRelaysDidChange()
        }
        UserDefaults.standard.set(vineAutoplayAudio, forKey: "vine_autoplay_audio_enabled")
        if followingHashtags != originalFollowingHashtags, let account = feed.account {
            account.followingHashtags = followingHashtags
            account.publishNewContactList()
        }
        feed.markUserEdited()
        DataProvider.shared().saveToDiskNow(.viewContext)
    }

    func cancel() {
        guard !didFinish else { return }
        didFinish = true
        feed.setValuesForKeys(originalValues)
        if feed.mediaFeedSource != originalMediaSource {
            feed.mediaFeedSource = originalMediaSource
        }
        feed.managedObjectContext?.processPendingChanges()
        DataProvider.shared().saveToDiskNow(.viewContext)
    }
}

struct FeedSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft: FeedSettingsDraft
    private let onClose: (() -> Void)?

    init(feed: CloudFeed, onClose: (() -> Void)? = nil) {
        _draft = StateObject(wrappedValue: FeedSettingsDraft(feed: feed))
        self.onClose = onClose
    }

    var body: some View {
        NRSheetNavigationStack {
            FeedSettings(feed: draft.feed, draft: draft)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            draft.cancel()
                            close()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            draft.apply()
                            close()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Done")
                    }
                }
        }
        .interactiveDismissDisabled()
    }

    private func close() {
        if let onClose {
            onClose()
        }
        else {
            dismiss()
        }
    }
}

struct FeedSettings: View {
    public var feed: CloudFeed
    var draft: FeedSettingsDraft? = nil

    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        switch feed.type {
        case "following":
            FollowingFeedSettings(feed: feed, draft: draft)
            
        case "picture":
            PictureFeedSettings(feed: feed, draft: draft)
            
        case "yak":
            YakFeedSettings(feed: feed, draft: draft)

        case "vine":
            VineFeedSettings(feed: feed, draft: draft)
            
        case "relays":
            RelayFeedSettings(feed: feed)
            
        case "pubkeys", nil, "30000", "39089":
            ContactFeedSettings(feed: feed)

        default:
            Rectangle()
                .frame(width: 100, height: 100)
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
                    FeedSettingsSheet(feed: feed)
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
    @Environment(\.containerID) private var containerID
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
                        navigateToContact(pubkey: nrContact.pubkey,  context: containerID)
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
