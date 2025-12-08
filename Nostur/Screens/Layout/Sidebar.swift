//
//  Sidebar.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/09/2023.
//

import SwiftUI
import NavigationBackport

let NOSTUR_SIDEBAR_WIDTH = 310.0

struct SideBar: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @EnvironmentObject private var dm: DirectMessageViewModel
    @Binding var showSidebar: Bool
    
    @State private var accountsSheetIsShown = false
    @State private var logoutAccount: CloudAccount? = nil
    @State private var showAnySigner = false
    @State private var sidebarOffset: CGFloat = -NOSTUR_SIDEBAR_WIDTH
    @State private var npub = ""
    
    static let ICON_WIDTH = 30.0
    static let MENU_TEXT_WIDTH = NOSTUR_SIDEBAR_WIDTH - 70.0
    static let BUTTON_VPADDING = 12.0
    
    private var account: CloudAccount {
        loggedInAccount.account
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        VStack(alignment: .leading) {
            ProfileBanner(banner: account.banner, width: NOSTUR_SIDEBAR_WIDTH)
                .overlay(alignment: .bottomLeading, content: {
                    PFP(pubkey: account.publicKey, account: account, size: 75) 
                        .equatable()
                        .overlay(
                            Circle()
                                .strokeBorder(theme.listBackground, lineWidth: 3)
                        )
                        .onTapGesture {
                            if IS_IPAD && !IS_DESKTOP_COLUMNS() {
                                showSidebar = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    navigateTo(ContactPath(key: account.publicKey, navigationTitle: account.anyName), context: "Default")
                                }
                            }
                            else {
                                if selectedTab() != "Main" {
                                    setSelectedTab("Main")
                                }
                                navigateTo(ContactPath(key: account.publicKey), context: "Default")
                                showSidebar = false
                            }
                        }
                        .offset(x: 10, y: 37)
                })
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 10) {
                        Spacer()
                        FastAccountSwitcher(activePubkey: account.publicKey, showSidebar: $showSidebar)
                            .equatable()
                        Button { accountsSheetIsShown = true } label: {
                            Image(systemName: "ellipsis.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                                .foregroundColor(theme.accent)
                        }
                    }
                    .zIndex(20)
                    .offset(x: -10, y: 37)
                }
                .zIndex(30)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading) {
                            Text("\(account.name)").font(.headline)
                            CopyableTextView(text: account.npub)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                            Text("**\(account.followingPubkeys.count)**  Following", comment: "Number of people following").font(.caption)
                        }
                        Spacer()
                        NWCWalletBalance()
                    }
                    .padding(.bottom, 20)
                     
                    Button {
                        if IS_IPAD && !IS_DESKTOP_COLUMNS() {
                            showSidebar = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                navigateTo(ContactPath(key: account.publicKey), context: "Default")
                            }
                        }
                        else {
                            if selectedTab() != "Main" {
                                setSelectedTab("Main")
                            }
                            navigateTo(ContactPath(key: account.publicKey), context: "Default")
                            showSidebar = false
                        }
                    } label: {
                        Label(
                            title: { 
                                Text("Profile", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "person")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                    }
                    Button {
                        if selectedTab() != "Main" {
                            setSelectedTab("Main")
                        }
                        navigateToOnMain(ViewPath.Lists)
                        showSidebar = false
                    } label: {
                        Label(
                            title: { 
                                Text("Lists & Feeds", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "list.bullet.rectangle")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                    }
                    Button {
                        setSelectedTab("Bookmarks")
                        showSidebar = false
                    } label: {
                        Label(
                            title: {
                                Text("Bookmarks", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "bookmark")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                    }
                    
                    // Only on iPhone/iPad 26.0, never on macOS
                    // (macOS 26 has own custom tabbar with DM button still)
                    // (pre-26.0 has old tabbar with DM button still)
                    if #available(iOS 26.0, *), !IS_CATALYST {
                        Button {
                            if selectedTab() != "Main" {
                                setSelectedTab("Main")
                            }
                            navigateToOnMain(ViewPath.DMs)
                            showSidebar = false
                        } label: {
                            Label(
                                title: {
                                    Text("Messages", comment: "Side bar navigation button")
                                        .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                                },
                                icon: {
                                    Image(systemName: "envelope")
                                        .frame(width: Self.ICON_WIDTH)
                                        .overlay(alignment: .topTrailing) {
                                            if (dm.unread + dm.newRequests) > 0 {
                                                Text("\((dm.unread + dm.newRequests))")
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 7 > 99 ? 4 : 6)
                                                    .padding(.vertical, 2)
                                                    .background(.red)
                                                    .clipShape(Capsule())
                                                    .offset(x: 5, y: -6)
                                            }
                                        }
                                    
                                }
                            )
                            .padding(.vertical, Self.BUTTON_VPADDING)
                            .contentShape(Rectangle())
                        }
                    }
                    
                    if !account.isNC {
                        Button {
                            if selectedTab() != "Main" {
                                setSelectedTab("Main")
                            }
                            navigateToOnMain(ViewPath.Badges)
                            showSidebar = false
                        } label: {
                            Label(
                                title: {
                                    Text("Badges", comment: "Side bar navigation button")
                                        .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                                },
                                icon: {
                                    if #available(iOS 16, *) {
                                        Image(systemName: "medal")
                                            .frame(width: Self.ICON_WIDTH)
                                    }
                                    else {
                                        Image(systemName: "rosette")
                                            .frame(width: Self.ICON_WIDTH)
                                    }
                                }
                            )
                            .padding(.vertical, Self.BUTTON_VPADDING)
                            .contentShape(Rectangle())
                        }
                    }
                    Button {
                        if selectedTab() != "Main" {
                            setSelectedTab("Main")
                        }
                        navigateToOnMain(ViewPath.Settings)
                        showSidebar = false
                    } label: {
                        Label(
                            title: {
                                Text("Settings", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "gearshape")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                    }
                    Button {
                        if selectedTab() != "Main" {
                            setSelectedTab("Main")
                        }
                        navigateToOnMain(ViewPath.Blocklist)
                        showSidebar = false
                    } label: {
                        Label(
                            title: {
                                Text("Block list", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "person.badge.minus")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                    }
                    if !account.isNC {
                        Button {
                            showAnySigner = true
                        } label: {
                            Label(
                                title: {
                                    Text("Signer", comment: "Side bar navigation button")
                                        .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                                },
                                icon: { Image(systemName: "signature")
                                    .frame(width: Self.ICON_WIDTH) }
                            )
                            .padding(.vertical, Self.BUTTON_VPADDING)
                            .contentShape(Rectangle())
                        }
                    }
                    Button {
                        logoutAccount = account
                    } label: {
                        Label(
                            title: {
                                Text("Log out", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "rectangle.portrait.and.arrow.right")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                    }
                }
                .padding(10)
            }
            .zIndex(20)
            .padding(.top, 45)
            Spacer()
            VStack(alignment: .leading) {
                Text("Nostur \(APP_VERSION) (Build: \(CI_BUILD_NUMBER))")
                    .font(.footnote)
#if DEBUG
                    .foregroundColor(Color.red) // So we can quickly check if we are in debug or release build
#endif
                    .opacity(0.5)
                Text("[__Source code__](https://github.com/nostur-com/nostur-ios-public)")
                    .foregroundColor(theme.accent)
                    .font(.footnote)
                    .padding(.bottom, 20)
            }
            .padding(10)
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $accountsSheetIsShown) {
            NBNavigationStack {
                AccountsSheet(onDismiss: {
                    accountsSheetIsShown = false
                    showSidebar = false
                })
                    .presentationDetents45ml()
                    .environment(\.theme, theme)
                    .environmentObject(loggedInAccount)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $showAnySigner) {
            NBNavigationStack {
                AnySigner()
                    .environment(\.theme, theme)
                    .environmentObject(loggedInAccount)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(item: $logoutAccount, content: { _ in
            NBNavigationStack {
                LogoutAccountSheet(account: $logoutAccount, showSidebar: $showSidebar)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
            .presentationDetents350l()
        })
        .background(theme.listBackground)
        .compositingGroup()
        .opacity(showSidebar ? 1.0 : 0)
        .offset(x: sidebarOffset)
        .onChange(of: showSidebar) { newValue in
            withAnimation(.easeOut(duration: 0.1)) {
                sidebarOffset = newValue ? 0 : -NOSTUR_SIDEBAR_WIDTH
            }
        }
    }
}

struct SideBarOverlay: View {
    @Environment(\.theme) private var theme
    @Binding var showSidebar: Bool
    
    var body: some View {
        theme.listBackground
            .opacity(showSidebar ? 0.75 : 0.0)
            .onTapGesture {
                showSidebar = false // TODO: Add swipe left/right to show/hide side menu
            }
    }
}

struct WithSidebar<Content: View>: View {
    @State private var showSidebar: Bool = false
    
    @ViewBuilder
    public let content: Content
    
    var body: some View {
        content
            .environment(\.showSidebar, $showSidebar)
            .overlay {
                SideBarOverlay(showSidebar: $showSidebar)
                    .opacity(showSidebar ? 1.0 : 0.0)
            }
            .overlay(alignment: .topLeading) {
                SideBar(showSidebar: $showSidebar)
                    .frame(width: NOSTUR_SIDEBAR_WIDTH)
                    .edgesIgnoringSafeArea(.all)
                    .opacity(showSidebar ? 1.0 : 0.0)
            }
    }
}

struct ShowSidebarEnvironmentKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showSidebar:  Binding<Bool> {
        get { self[ShowSidebarEnvironmentKey.self] }
        set { self[ShowSidebarEnvironmentKey.self] = newValue }
    }
}

#Preview("Side bar menu") {
    PreviewContainer {
        VStack {
            if let loggedInAccount = AccountsState.shared.loggedInAccount {
                NosturMainView()
                    .environmentObject(loggedInAccount)
            }
        }
    }
}

#Preview("Side bar menu with feed") {
    PreviewContainer({ pe in
        pe.parseMessages([
            
            // host profile info
            ###"["EVENT", "contact", {"kind":0,"id":"763a7412148cca4074e9e68a0bc16e5bd1821524bdc5593cb178de199e42fcc6","pubkey":"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","created_at":1719904036,"tags":[],"content":"{\"name\":\"ZapLamp\",\"picture\":\"https://nostrver.se/sites/default/files/2024-07/IMG_1075.jpeg\",\"about\":\"A side-project of @npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe Send some sats with a zap to see the lamp flash on the livestream\",\"website\":\"https://nostrver.se\",\"lud16\":\"sebastian@lnd.sebastix.com\",\"display_name\":\"ZapLamp ⚡💜\",\"displayName\":\"ZapLamp ⚡💜\",\"nip05\":\"zaplamp@nostrver.se\",\"pubkey\":\"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85\"}","sig":"e1266f8131cae6a457791114cda171031b79538f8bd710fbef45a2c36265045eb641914719b949509dcbf725c2b1f8522dffb5556b3e3f7d4db9d039a9e6daa0"}]"###,
            
            // live event
            ###"["EVENT","LIVEEVENT-LIVE2",{"kind":30311,"id":"03082afe5364b086293a60c3fc982d5265083af66b726cecd0978d3f0d5be1e0","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720098927,"tags":[["d","569180c5-adec-40a6-a41b-513f39ded13a"],["title",""],["summary","Send a zap to flash the lamp! There is a ~15 sec between your zap and the stream."],["image","https://dvr.zap.stream/zap-stream-dvr/569180c5-adec-40a6-a41b-513f39ded13a/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277007695\u0026Signature=Zqbwvwam70uT9UKRBW0fmHHzLrI%3D"],["status","live"],["p","9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1719911364"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/569180c5-adec-40a6-a41b-513f39ded13a.m3u8"],["current_participants","0"],["t","zaplamp"],["t","lnbits"],["t","zapathon"],["t","internal:art"],["goal","66d73e8f3de742e70e3f5b1c30ff2a028fae0d4f1efad53089172e5c05563579"]],"content":"","sig":"4321619ff3aa63387aefc7403baea01317a7c408cfa2547546046e354e4a765af886ee9c509f1ca6043be7cf01bdff696cf521261316c5261a2a42eed87e5289"}]"###,
            
            // profile
            ###"["EVENT", "x", {"kind":0,"id":"63617e02e87940abf6ecc93368330adae663538237d171d4e5177465f5208eba","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9712224322,"tags":[],"content":"{\"nip05\":\"_@zap.stream\",\"name\":\"zap.stream\",\"picture\":\"https://zap.stream/logo.png\",\"website\":\"https://zap.stream\",\"about\":\"Keep 100% of your tips when you stream with http://zap.stream! Powered by #bitcoin \u0026 #nostr\"}","sig":"316c38e1b67d4757bf152ec3c4756a1c9f3d47218fef8b06c5bacf7c96c27e1ce6297caf7a7c7887f9b01f6c92f2d4b26722722062b2243f44c252d0d432eefc"}]"###,
            
            // live event
            ###"["EVENT", "LIVEEVENT-LIVE", {"kind":30311,"id":"8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720103970,"tags":[["d","34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f"],["title","BTC Sessions LIVE"],["summary","You are the DJ on Noderunners Radio!"],["image","https://dvr.zap.stream/zap-stream-dvr/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277012770\u0026Signature=n4l1GWDFvBLm8ZtAp%2BIss%2BjmBUk%3D"],["status","live"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","","speaker"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","","host"],["p","2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884","","speaker"],["p","eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","","speaker"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1720089226"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f.m3u8"],["current_participants","2"],["t","Jukebox"],["t","Music"],["t","Radio"],["t","24/7"],["t","Pleb-Rule"],["goal","1b8460c1f1590aecd340fcb327c21fb466f46800aba7bd7b6ac6b0a2257f7789"]],"content":"","sig":"d3b07150e70a36009a97c0953d8c2c759b364301e92433cb0a31d5dcfffc2dabcc6d6f330054a2cae30a7ecc16dbd8ddf1e05f9b7553c88a5d9dece18a2000bc"}]"###
        ])
        pe.loadContacts()
        pe.loadPosts()
        pe.loadFollows()
    }) {
        VStack {
            if let loggedInAccount = AccountsState.shared.loggedInAccount {
                NosturMainView()
                    .environmentObject(loggedInAccount)
            }
        }
    }
}
