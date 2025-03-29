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
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @Binding var showSidebar: Bool
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
    }
    
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
        let _ = Self._printChanges()
        #endif
        VStack(alignment: .leading) {
            ProfileBanner(banner: account.banner, width: NOSTUR_SIDEBAR_WIDTH)
                .overlay(alignment: .bottomLeading, content: {
                    PFP(pubkey: account.publicKey, account: account, size: 75) 
                        .equatable()
                        .overlay(
                            Circle()
                                .strokeBorder(themes.theme.background, lineWidth: 3)
                        )
                        .onTapGesture {
                            if IS_IPAD {
                                showSidebar = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    navigateTo(ContactPath(key: account.publicKey, navigationTitle: account.anyName))
                                }
                            }
                            else {
                                navigateTo(ContactPath(key: account.publicKey))
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
                                .foregroundColor(themes.theme.accent)
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
                        if IS_IPAD {
                            showSidebar = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                navigateTo(ContactPath(key: account.publicKey))
                            }
                        }
                        else {
                            navigateTo(ContactPath(key: account.publicKey))
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
                        .overlay(alignment: .bottom) {
                            themes.theme.lineColor
                                .frame(height: 1)
                        }
                    }
                    Button {
                        if selectedTab != "Main" { 
                            UserDefaults.standard.setValue("Main", forKey: "selected_tab")
                        }
                        navigateToOnMain(ViewPath.Lists)
                        showSidebar = false
                    } label: {
                        Label(
                            title: { 
                                Text("Feeds", comment: "Side bar navigation button")
                                    .frame(width: Self.MENU_TEXT_WIDTH, alignment: .leading)
                            },
                            icon: { Image(systemName: "list.bullet.rectangle")
                                .frame(width: Self.ICON_WIDTH) }
                        )
                        .padding(.vertical, Self.BUTTON_VPADDING)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            themes.theme.lineColor
                                .frame(height: 1)
                        }
                    }
                    Button {
                        UserDefaults.standard.setValue("Bookmarks", forKey: "selected_tab")
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
                        .overlay(alignment: .bottom) {
                            themes.theme.lineColor
                                .frame(height: 1)
                        }
                    }
                    if !account.isNC {
                        Button {
                            if selectedTab != "Main" {
                                UserDefaults.standard.setValue("Main", forKey: "selected_tab")
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
                            .overlay(alignment: .bottom) {
                                themes.theme.lineColor
                                    .frame(height: 1)
                            }
                        }
                    }
                    Button {
                        if selectedTab != "Main" {
                            UserDefaults.standard.setValue("Main", forKey: "selected_tab")
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
                        .overlay(alignment: .bottom) {
                            themes.theme.lineColor
                                .frame(height: 1)
                        }
                    }
                    Button {
                        if selectedTab != "Main" {
                            UserDefaults.standard.setValue("Main", forKey: "selected_tab")
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
                        .overlay(alignment: .bottom) {
                            themes.theme.lineColor
                                .frame(height: 1)
                        }
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
                            .overlay(alignment: .bottom) {
                                themes.theme.lineColor
                                    .frame(height: 1)
                            }
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
                    .foregroundColor(themes.theme.accent)
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
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .sheet(isPresented: $showAnySigner) {
            NBNavigationStack {
                AnySigner()
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .actionSheet(item: $logoutAccount) { account in
            ActionSheet(
                title: Text("Confirm log out", comment: "Action sheet title"),
                message: !account.isNC && account.privateKey != nil
                ? Text("""
                                 Make sure you have a back-up of your private key (nsec)
                                 Nostur cannot recover your account without it
                                 """, comment: "informational message")
                : Text("""
                                 Account: @\(account.name) / \(account.display_name)
                                 """, comment: "informational message showing account name(s)")
                ,
                buttons: !account.isNC && account.privateKey != nil ? [
                    .destructive(Text("Log out", comment: "Log out button"), action: {
                        AccountsState.shared.logout(account)
                        showSidebar = false
                    }),
                    .default(Text("Copy private key (nsec) to clipboard", comment: "Button to copy private key to clipboard"), action: {
                        if let pk = account.privateKey {
                            UIPasteboard.general.string = nsec(pk)
                        }
                    }),
                    .cancel(Text("Cancel"))
                ] : [
                    .destructive(Text("Log out", comment:"Log out button"), action: {
                        AccountsState.shared.logout(account)
                        showSidebar = false
                    }),
                    .cancel(Text("Cancel"))
                ])
        }
        .background(themes.theme.listBackground)
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
    @EnvironmentObject private var themes: Themes
    @Binding var showSidebar: Bool
    
    var body: some View {
        themes.theme.listBackground
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
