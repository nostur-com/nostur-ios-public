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

import NostrEssentials

func handleUrl(_ url: URL) {
#if DEBUG
    L.og.debug("handleUrl: \(url.absoluteString)")
#endif
    
    // HANDLE ADD RELAY FEED
    let nosturRelay = url.absoluteString.matchingStrings(regex: "^(nostur:add_relay:)(\\S+)$")
    if nosturRelay.count == 1 && nosturRelay[0].count == 3 {
#if DEBUG
        L.og.info("nostur: add_relay: \(nosturRelay[0][2])")
 #endif
        AppSheetsModel.shared.relayFeedPreviewSheetInfo = RelayFeedPreviewInfo(relayUrl: normalizeRelayUrl(nosturRelay[0][2]))
        return
    }

    // NOSTR LOGIN
    let nostrlogin = url.absoluteString.matchingStrings(regex: "^nostr\\+login:(.*):([a-zA-Z0-9\\-_\\.]+)$")
    if nostrlogin.count == 1 && nostrlogin[0].count >= 3 {
        // can login even?
        if AccountsState.shared.bgFullAccountPubkeys.count > 0 {
            
            let domainString = nostrlogin[0][1]
            let challenge = nostrlogin[0][2]
            if let domain = URL(string: "https://" + domainString), let host = domain.host {
#if DEBUG
                L.og.debug("Login to: \(host)?")
#endif
                AppSheetsModel.shared.askLoginInfo = AskLoginInfo(domain: host, challenge: challenge)
                return
            }
        }
        else {
            let domainString = nostrlogin[0][1]
            if let domain = URL(string: "https://" + domainString), let host = domain.host {
                sendNotification(.anyStatus, ("Login requested on \(host) but no keys.", "APP_NOTICE"))
            }
        }
        return
    }

    if let regex = try? NSRegularExpression(pattern: "^nostr+login:(.*):([a-zA-Z0-9\\-_\\.]+)$", options: .caseInsensitive) {
        let nsRange = NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)
        if regex.firstMatch(in: url.absoluteString, options: [], range: nsRange) != nil {
#if DEBUG
            L.og.info("Handle nostr login")
#endif
            return
        }
    }

    // CALLBACK FROM NWC
    if #available(iOS 16.0, *) {
        if let _ = url.absoluteString.firstMatch(of: /^nostur:\/\/nwc_callback(.*)/) {
            sendNotification(.nwcCallbackReceived, AlbyCallback(url:url))
            return
        }
    } else {
        if let regex = try? NSRegularExpression(pattern: "^nostur://nwc_callback(.*)", options: .caseInsensitive) {
            let nsRange = NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)
            if regex.firstMatch(in: url.absoluteString, options: [], range: nsRange) != nil {
                sendNotification(.nwcCallbackReceived, AlbyCallback(url: url))
                return
            }
        }
    }

    // LINKS FROM ANYWHERE (NPUB1/NOTE1)
    let nostr = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
    if nostr.count == 1 && nostr[0].count == 4 {
#if DEBUG
        L.og.info("nostr: link: \(nostr[0][2])\(nostr[0][3])")
#endif
        let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
#if DEBUG
        L.og.info("nostr: link::  \(key.hexString)")
#endif
        
        setSelectedTab("Main")
        if nostr[0][2] == "npub1" {
            navigateTo(ContactPath(key: key.hexString), context: "Default")
            return
        }
        if nostr[0][2] == "note1" {
            navigateTo(NotePath(id: key.hexString), context: "Default")
            return
        }
    }

    // NADDR ARTICLE
    let nostrAddr = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(naddr1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
    if nostrAddr.count == 1 && nostrAddr[0].count == 4 {
#if DEBUG
        L.og.info("nostr: naddr: \(nostrAddr[0][2])\(nostrAddr[0][3])")
#endif
        setSelectedTab("Main")
        navigateTo(Naddr1Path(naddr1: "\(nostrAddr[0][2])\(nostrAddr[0][3])"), context: "Default")
        return
    }

    // (NEW) LINKS FROM ANYWHERE (NEVENT1/NPROFILE1)
    let nostrSharable = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(nevent1|nprofile1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
    if nostrSharable.count == 1 && nostrSharable[0].count == 4 {
#if DEBUG
        L.og.info("nostr: nevent1/nprofile1: \(nostrSharable[0][2])\(nostrSharable[0][3])")
#endif
        setSelectedTab("Search")
        if nostrSharable[0][2] == "nevent1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // TODO: Make proper loading into Search tab, instead of hoping the tab has loaded in time for .onReceive(receiveNotification(.navigateTo))
                navigateTo(Nevent1Path(nevent1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"), context: "Search")
            }
            return
        }
        if nostrSharable[0][2] == "nprofile1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // TODO: Make proper loading into Search tab, instead of hoping the tab has loaded in time for .onReceive(receiveNotification(.navigateTo))
                navigateTo(Nprofile1Path(nprofile1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"), context: "Search")
            }
            return
        }
    }

    // LINKS FROM WITHIN NOSTUR
    let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
    if nostur.count == 1 && nostur[0].count == 4 {
#if DEBUG
        L.og.info("nostur: link: \(nostur[0][2])\(nostur[0][3])")
    #endif
        if nostur[0][2] == "p:" {
            // Small delay to make sure AppState.shared.containerIDTapped is set (via  .simultaneousGesture(TapGesture()...)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                navigateTo(ContactPath(key: nostur[0][3]), context: AppState.shared.containerIDTapped)
            }
            return
        }
        if nostur[0][2] == "e:" {
            // Small delay to make sure AppState.shared.containerIDTapped is set (via  .simultaneousGesture(TapGesture()...)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                navigateTo(NotePath(id: nostur[0][3]), context: AppState.shared.containerIDTapped)
            }
            return
        }
    }

    // LINKS FROM ANYWHERE (HEX)
    let nostrHex = url.absoluteString.matchingStrings(regex: "^(nostr:)(p:|e:)([0-9a-z]{64})$")
    if nostrHex.count == 1 && nostrHex[0].count == 4 {
#if DEBUG
        L.og.info("nostur: link: \(nostrHex[0][2])\(nostrHex[0][3])")
#endif
        
        setSelectedTab("Main")
        if nostrHex[0][2] == "p:" {
            navigateTo(ContactPath(key: nostrHex[0][3]), context: "Default")
            return
        }
        if nostrHex[0][2] == "e:" {
            navigateTo(NotePath(id: nostrHex[0][3]), context: "Default")
            return
        }
    }

    // HASHTAG LINKS FROM WITHIN NOSTUR
    let nosturHashtag = url.absoluteString.matchingStrings(regex: "^(nostur:t:)(\\S+)$")
    if nosturHashtag.count == 1 && nosturHashtag[0].count == 3 {
#if DEBUG
        L.og.info("nostur: hashtag: \(nosturHashtag[0][2])")
#endif
        setSelectedTab("Search")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            navigateTo(HashtagPath(hashTag: nosturHashtag[0][2]), context: "Search")
        }
        return
    }

    // SHARE NEW HIGHLIGHT
    if #available(iOS 16.0, *) {
        if let newHighlight = url.absoluteString.firstMatch(of: /^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$/) {
#if DEBUG
            L.og.info("nostur: highlight")
#endif
            guard let url = newHighlight.output.4.removingPercentEncoding else { return }
            guard let selectedText = newHighlight.output.2.removingPercentEncoding else { return }
            let title = newHighlight.output.6.removingPercentEncoding
            sendNotification(.newHighlight, NewHighlight(url: url, selectedText: selectedText, title: title))
            return
        }
    } else {
        // Fallback on earlier versions
        let pattern = "^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: url.absoluteString, options: [], range: NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)) {
#if DEBUG
            L.og.info("nostur: highlight")
#endif
            let ranges = (1..<regex.numberOfCaptureGroups + 1).map { match.range(at: $0) }
            guard ranges.count == 6 else { return }

            let substrings = ranges.map { Range($0, in: url.absoluteString).map { url.absoluteString[$0] } }
            guard let url = substrings[3]?.removingPercentEncoding,
                  let selectedText = substrings[1]?.removingPercentEncoding else { return }

            let title = substrings[5]?.removingPercentEncoding

            sendNotification(.newHighlight, NewHighlight(url: url, selectedText: selectedText, title: title))
            return
        }

    }
}
