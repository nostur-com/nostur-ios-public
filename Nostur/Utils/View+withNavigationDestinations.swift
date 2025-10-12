//
//  View+withNavigationDestinations.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

import Foundation
import SwiftUI
import NavigationBackport

struct NotePath: IdentifiableDestination {
    var id: String
    var navigationTitle: String? = nil
}

struct ContactPath: IdentifiableDestination {
    var id: String { key }
    var key: String
    var navigationTitle: String? = nil
    var tab: String? = nil
}

struct NRContactPath: IdentifiableDestination {
    var id: String { nrContact.pubkey }
    var nrContact: NRContact
    var navigationTitle: String? = nil
    var tab: String? = nil
}

struct HashtagPath: IdentifiableDestination {
    var id: String { hashTag }
    var hashTag: String
    var navigationTitle: String? = nil
}

struct Nevent1Path: IdentifiableDestination {
    var id: String { nevent1 }
    var nevent1: String
    var navigationTitle: String? = nil
}

struct Naddr1Path: IdentifiableDestination {
    public var id: String { naddr1 }
    public var naddr1: String
    public var navigationTitle: String? = nil
    
    public var kind: Int { // -999999912 means we dont have a kind
        Int((try? ShareableIdentifier(naddr1).kind) ?? -999899912)
    }
    
    public var pubkey: String {
        (try? ShareableIdentifier(naddr1).pubkey) ?? "oops"
    }
    
    public var dTag: String {
        (try? ShareableIdentifier(naddr1).eventId) ?? ""
    }
    
    public var navId: String { 
        (try? ShareableIdentifier(naddr1))?.aTag ?? id
    }
    
    init(naddr1: String, navigationTitle: String? = nil) {
        self.naddr1 = naddr1
        self.navigationTitle = navigationTitle
    }
}

struct ArticlePath: IdentifiableDestination {
    var id: String
    var navigationTitle: String? = nil
}

struct Nprofile1Path: IdentifiableDestination {
    var id: String { nprofile1 }
    var nprofile1: String
    var navigationTitle: String? = nil
}

struct ArticleCommentsPath: Identifiable, IdentifiableDestination {
    var id: String { article.id }
    let article: NRPost
}

enum ViewPath: IdentifiableDestination {
    var id: String { UUID().uuidString }
    
    case Post(nrPost: NRPost)
    case Blocklist
    case Bookmarks(account: CloudAccount)
    case PostReactions(eventId: String)
    case PostReposts(id: String)
    case PostZaps(nrPost: NRPost)
    case Settings
    case Lists
    case Relays
    case Badges
    case DMs
    case Gallery(vm: GalleryViewModel)
    case ProfileReactionList(pubkey: String)
}

struct NavigationDestinationsModifier: ViewModifier {
    @Environment(\.containerID) var containerID
    
    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .nbNavigationDestination(for: NRPost.self) { nrPost in
                switch nrPost.kind {
                case 30023:
                    ArticleView(nrPost, isDetail: true, fullWidth: SettingsStore.shared.fullWidthImages, hideFooter: false)
                        .environment(\.containerID, self.containerID)
                case 30311:
                    if let nrLiveEvent = nrPost.nrLiveEvent {
                        LiveEventDetail(liveEvent: nrLiveEvent)
                            .environment(\.containerID, self.containerID)
                    }
                    else {
                        Text("Missing nrLiveEvent")
                    }
                default:
                    PostDetailView(nrPost: nrPost)
                        .environment(\.containerID, self.containerID)
//                        .equatable()
//                        .debugDimensions("nbNavigationDestination.PostDetailView", alignment: .topLeading)
                }
            }
            .nbNavigationDestination(for: Naddr1Path.self) { path in
                switch path.kind {
                case 30311:
                    LiveEventByNaddr(naddr1: path.naddr1, navigationTitle: path.navigationTitle)
                        .environment(\.containerID, self.containerID)
                default:
                    ArticleByNaddr(naddr1: path.naddr1, navigationTitle: path.navigationTitle)
                        .environment(\.containerID, self.containerID)
                }
            }
            .nbNavigationDestination(for: NRLiveEvent.self) { nrLiveEvent in
                LiveEventDetail(liveEvent: nrLiveEvent)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: ArticlePath.self) { path in
                ArticleById(id: path.id, navigationTitle: path.navigationTitle)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: ArticleCommentsPath.self) { articleCommentsPath in
                ArticleCommentsView(article: articleCommentsPath.article)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: NotePath.self) { path in
                NoteById(id: path.id)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: ContactPath.self) { path in
                ProfileByPubkey(pubkey: path.key, tab: path.tab)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: NRContactPath.self) { path in
                ProfileView(nrContact: path.nrContact, tab: path.tab)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: NRContact.self) { nrContact in
                ProfileView(nrContact: nrContact)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: Badge.self) { badge in
                BadgeDetailView(badge: badge.badge)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: CloudFeed.self) { feed in
                FeedSettings(feed: feed)
                    .environment(\.containerID, self.containerID)
            }
            .nbNavigationDestination(for: ViewPath.self) { path in
                switch (path) {
                    case .Post(let post):
                        PostDetailView(nrPost: post)
                            .environment(\.containerID, self.containerID)
                    case .Blocklist:
                        BlockListScreen()
                            .tabBarSpaceCompat()
                            .environment(\.containerID, self.containerID)
                    case .PostReactions(let eventId):
                        PostReactions(eventId: eventId)
                            .environment(\.containerID, self.containerID)
                    case .PostReposts(let id):
                        PostReposts(id: id)
                            .environment(\.containerID, self.containerID)
                    case .PostZaps(let nrPost):
                        PostZaps(nrPost: nrPost)
                            .environment(\.containerID, self.containerID)
                    case .Settings:
                        Settings()
                            .tabBarSpaceCompat()
                            .environment(\.containerID, self.containerID)
                    case .Lists:
                        ListsAndFeedsScreen()
                            .tabBarSpaceCompat()
                            .environment(\.containerID, self.containerID)
                    case .Relays:
                        RelaysView()
                            .environment(\.containerID, self.containerID)
                    case .Badges:
                        BadgesView()
                            .tabBarSpaceCompat()
                            .environment(\.containerID, self.containerID)
                    case .DMs:
                        DMContainer()
                            .environment(\.containerID, self.containerID)
                    case .ProfileReactionList(let pubkey):
                        ProfileReactionList(pubkey: pubkey)
                            .tabBarSpaceCompat()
                            .environment(\.containerID, self.containerID)
                    default:
                        EmptyView()
                }
            }
    }
}

extension View {
    func withNavigationDestinations() -> some View {
        modifier(NavigationDestinationsModifier())
    }
}

struct NavigationDestination {
    let destination: any IdentifiableDestination
    let context: String
}

protocol IdentifiableDestination: Hashable, Identifiable {
    
}

func navigateTo(_ path: any IdentifiableDestination, context: String) {
    if (type(of: path) == NRPost.self) {
        let nrPost = path as! NRPost
        if nrPost.kind == 30023 {
            sendNotification(.navigateTo, NavigationDestination(destination: ArticlePath(id: nrPost.id, navigationTitle: nrPost.eventTitle ?? "Article"), context: context))
        }
        else {
            sendNotification(.navigateTo, NavigationDestination(destination: path, context: context))
        }
    }
    else {
        sendNotification(.navigateTo, NavigationDestination(destination: path, context: context))
    }
    
    // minimize stream
    if AnyPlayerModel.shared.isShown && AnyPlayerModel.shared.viewMode == .detailstream {
        AnyPlayerModel.shared.viewMode = .overlay
    }
    else if LiveKitVoiceSession.shared.visibleNest != nil {
        LiveKitVoiceSession.shared.visibleNest = nil
    }
}

func navigateToOnMain(_ path: any IdentifiableDestination) {
    sendNotification(.navigateToOnMain, NavigationDestination(destination: path, context: "Default"))
    // minimize stream
    if AnyPlayerModel.shared.isShown && AnyPlayerModel.shared.viewMode == .detailstream {
        AnyPlayerModel.shared.viewMode = .overlay
    }
    else if LiveKitVoiceSession.shared.visibleNest != nil {
        LiveKitVoiceSession.shared.visibleNest = nil
    }
}

func navigateOnDetail(_ path: any IdentifiableDestination) {
    sendNotification(.navigateToOnDetail, NavigationDestination(destination: path, context: "DetailPane"))
    // minimize stream
    if AnyPlayerModel.shared.isShown && AnyPlayerModel.shared.viewMode == .detailstream {
        AnyPlayerModel.shared.viewMode = .overlay
    }
    else if LiveKitVoiceSession.shared.visibleNest != nil {
        LiveKitVoiceSession.shared.visibleNest = nil
    }
}

// Navigate to contact helper
func navigateToContact(pubkey: String, nrContact: NRContact? = nil, nrPost: NRPost? = nil, context: String) {
    if let nrContact {
        navigateTo(nrContact, context: context)
    }
    else if let nrPost {
        navigateTo(nrPost.contact, context: context)
    }
    else {
        navigateTo(ContactPath(key: pubkey), context: context)
    }
    
    // minimize stream
    if AnyPlayerModel.shared.isShown && AnyPlayerModel.shared.viewMode == .detailstream {
        AnyPlayerModel.shared.viewMode = .overlay
    }
    else if LiveKitVoiceSession.shared.visibleNest != nil {
        LiveKitVoiceSession.shared.visibleNest = nil
    }
}
