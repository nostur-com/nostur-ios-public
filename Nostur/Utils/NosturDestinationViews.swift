//
//  NosturDestinationViews.swift
//  Nostur
//
//  Shared screens for both NavigationBackport and native NavigationStack.
//

import SwiftUI
import NavigationBackport

struct YearReviewDestination: View {
    let path: YearReviewPath
    let containerID: String

    var body: some View {
        if #available(iOS 17.0, *), YearReviewFeature.isEnabled {
            YearReviewView(initialYear: path.year)
                .environment(\.containerID, containerID)
        }
    }
}

struct NRPostDestination: View {
    let nrPost: NRPost
    let containerID: String

    var body: some View {
        switch nrPost.kind {
        case 30023:
            ArticleView(nrPost, isDetail: true, fullWidth: SettingsStore.shared.fullWidthImages, hideFooter: false)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        case 30009:
            BadgeDetailFromNRPost(nrPost: nrPost)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        case 30311:
            if let nrLiveEvent = nrPost.nrLiveEvent {
                LiveEventDetail(liveEvent: nrLiveEvent)
                    .environment(\.containerID, containerID)
                    .environmentObject(VideoPostPlaybackCoordinator())
            }
            else {
                Text("Missing nrLiveEvent")
            }
        case 22, 34236:
            ShortVideoDetailView(nrPost: nrPost)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        default:
            PostDetailView(nrPost: nrPost)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        }
    }
}

struct NaddrDestination: View {
    let path: Naddr1Path
    let containerID: String

    var body: some View {
        switch path.kind {
        case 30311:
            LiveEventByNaddr(naddr1: path.naddr1, navigationTitle: path.navigationTitle)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        case 30009:
            BadgeByNaddr(naddr1: path.naddr1, navigationTitle: path.navigationTitle)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        default:
            ArticleByNaddr(naddr1: path.naddr1, navigationTitle: path.navigationTitle)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        }
    }
}

struct LiveEventDestination: View {
    let nrLiveEvent: NRLiveEvent
    let containerID: String

    var body: some View {
        LiveEventDetail(liveEvent: nrLiveEvent)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct ArticlePathDestination: View {
    let path: ArticlePath
    let containerID: String

    var body: some View {
        ArticleById(id: path.id, navigationTitle: path.navigationTitle)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct ArticleCommentsDestination: View {
    let path: ArticleCommentsPath
    let containerID: String

    var body: some View {
        ArticleCommentsView(article: path.article)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct NotePathDestination: View {
    let path: NotePath
    let containerID: String

    var body: some View {
        NoteById(id: path.id)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct ContactPathDestination: View {
    let path: ContactPath
    let containerID: String

    var body: some View {
        ProfileByPubkey(pubkey: path.key, tab: path.tab)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct NRContactPathDestination: View {
    let path: NRContactPath
    let containerID: String

    var body: some View {
        ProfileView(nrContact: path.nrContact, tab: path.tab)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct NRContactDestination: View {
    let nrContact: NRContact
    let containerID: String

    var body: some View {
        ProfileView(nrContact: nrContact)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct BadgeDestination: View {
    let badge: Badge
    let containerID: String

    var body: some View {
        BadgeDetailView(badge: badge.badge)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct CloudFeedDestination: View {
    let feed: CloudFeed
    let containerID: String

    var body: some View {
        FeedSettingsSheet(feed: feed)
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
    }
}

struct ViewPathDestination: View {
    let path: ViewPath
    @Binding var navPath: NBNavigationPath
    let containerID: String

    var body: some View {
        switch path {
        case .Post(let post):
            Group {
                if post.kind == 22 || post.kind == 34236 {
                    ShortVideoDetailView(nrPost: post)
                }
                else {
                    PostDetailView(nrPost: post)
                }
            }
            .environment(\.containerID, containerID)
            .environmentObject(VideoPostPlaybackCoordinator())
        case .Blocklist:
            BlockListScreen()
                .tabBarSpaceCompat()
                .environment(\.containerID, containerID)
        case .PostReactions(let eventId):
            PostReactions(eventId: eventId)
                .environment(\.containerID, containerID)
        case .PostReposts(let id):
            PostReposts(id: id)
                .environment(\.containerID, containerID)
        case .PostMentions(let id):
            PostMentions(id: id)
                .environment(\.containerID, containerID)
        case .PostZaps(let nrPost):
            PostZaps(nrPost: nrPost)
                .environment(\.containerID, containerID)
        case .Wallet:
            WalletView()
                .tabBarSpaceCompat()
                .environment(\.containerID, containerID)
        case .Settings:
            Settings()
                .tabBarSpaceCompat()
                .environment(\.containerID, containerID)
        case .Lists:
            ListsAndFeedsScreen()
                .tabBarSpaceCompat()
                .environment(\.containerID, containerID)
        case .Relays:
            RelaysView()
                .environment(\.containerID, containerID)
        case .Badges:
            BadgesView()
                .tabBarSpaceCompat()
                .environment(\.containerID, containerID)
        case .DMs:
            MainDMs(navPath: $navPath)
                .environment(\.containerID, containerID)
        case .ProfileReactionList(let pubkey):
            ProfileReactionList(pubkey: pubkey)
                .tabBarSpaceCompat()
                .environment(\.containerID, containerID)
        default:
            EmptyView()
        }
    }
}

extension View {
    func backportStackDestinations(navPath: Binding<NBNavigationPath>, containerID: String) -> some View {
        self
            .nbNavigationDestination(for: YearReviewPath.self) { YearReviewDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: NewDMConversation.self) { newDMConversation in
                DMConversationView(participants: newDMConversation.participants, ourAccountPubkey: newDMConversation.accountPubkey, parentDMsVM: newDMConversation.parentDMsVM)
                    .environment(\.containerID, containerID)
                    .environmentObject(VideoPostPlaybackCoordinator())
            }
            .nbNavigationDestination(for: DMConversation.self) { dmConversation in
                DMConversationDestination(dmConversation: dmConversation, containerID: containerID)
            }
            .nbNavigationDestination(for: NRPost.self) { NRPostDestination(nrPost: $0, containerID: containerID) }
            .nbNavigationDestination(for: Naddr1Path.self) { NaddrDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: NRLiveEvent.self) { LiveEventDestination(nrLiveEvent: $0, containerID: containerID) }
            .nbNavigationDestination(for: ArticlePath.self) { ArticlePathDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: ArticleCommentsPath.self) { ArticleCommentsDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: NotePath.self) { NotePathDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: ContactPath.self) { ContactPathDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: NRContactPath.self) { NRContactPathDestination(path: $0, containerID: containerID) }
            .nbNavigationDestination(for: NRContact.self) { NRContactDestination(nrContact: $0, containerID: containerID) }
            .nbNavigationDestination(for: Badge.self) { BadgeDestination(badge: $0, containerID: containerID) }
            .nbNavigationDestination(for: CloudFeed.self) { CloudFeedDestination(feed: $0, containerID: containerID) }
            .nbNavigationDestination(for: ViewPath.self) { ViewPathDestination(path: $0, navPath: navPath, containerID: containerID) }
    }

    @available(iOS 16.0, *)
    func nativeStackDestinations(navPath: Binding<NBNavigationPath>, containerID: String) -> some View {
        self
            .navigationDestination(for: YearReviewPath.self) { YearReviewDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: NewDMConversation.self) { newDMConversation in
                DMConversationView(participants: newDMConversation.participants, ourAccountPubkey: newDMConversation.accountPubkey, parentDMsVM: newDMConversation.parentDMsVM)
                    .environment(\.containerID, containerID)
                    .environmentObject(VideoPostPlaybackCoordinator())
            }
            .navigationDestination(for: DMConversation.self) { DMConversationDestination(dmConversation: $0, containerID: containerID) }
            .navigationDestination(for: NRPost.self) { NRPostDestination(nrPost: $0, containerID: containerID) }
            .navigationDestination(for: Naddr1Path.self) { NaddrDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: NRLiveEvent.self) { LiveEventDestination(nrLiveEvent: $0, containerID: containerID) }
            .navigationDestination(for: ArticlePath.self) { ArticlePathDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: ArticleCommentsPath.self) { ArticleCommentsDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: NotePath.self) { NotePathDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: ContactPath.self) { ContactPathDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: NRContactPath.self) { NRContactPathDestination(path: $0, containerID: containerID) }
            .navigationDestination(for: NRContact.self) { NRContactDestination(nrContact: $0, containerID: containerID) }
            .navigationDestination(for: Badge.self) { BadgeDestination(badge: $0, containerID: containerID) }
            .navigationDestination(for: CloudFeed.self) { CloudFeedDestination(feed: $0, containerID: containerID) }
            .navigationDestination(for: ViewPath.self) { ViewPathDestination(path: $0, navPath: navPath, containerID: containerID) }
    }
}

private struct DMConversationDestination: View {
    let dmConversation: DMConversation
    let containerID: String

    var body: some View {
        if let accountPubkey = dmConversation.dmState.accountPubkey_ {
            DMConversationView(participants: dmConversation.dmState.participantPubkeys, ourAccountPubkey: accountPubkey, parentDMsVM: dmConversation.parentDMsVM)
                .environment(\.containerID, containerID)
                .environmentObject(VideoPostPlaybackCoordinator())
        }
        else {
            Text("Unavailable: accountPubkey missing")
        }
    }
}
