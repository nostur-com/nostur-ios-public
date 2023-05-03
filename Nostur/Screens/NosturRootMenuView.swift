//
//  NosturRootMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

let NOSTUR_SIDEBAR_WIDTH = 310.0

struct NosturRootMenu: View {
    let account:Account
    @StateObject private var sm = SideBarModel()
    
    var body: some View {
        let _ = Self._printChanges()
        SideBarStack(sidebarWidth: NOSTUR_SIDEBAR_WIDTH) {
            SideBar(account: account)
        } content: {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                Text("NosturTabsView()")
                    .frame(width: UIScreen.main.bounds.width)
                    .onAppear {
                        sm.showSidebar = true
                    }
            }
            else {
                NosturTabsView()
            }
        }
        .environmentObject(sm)
    }
}

struct SideBar: View {
    let ns:NosturState = .shared
    @EnvironmentObject var sm:SideBarModel
    @ObservedObject var account:Account
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var accountsSheetIsShown = false
    @State var logoutAccount:Account? = nil
    
    var body: some View {
        let _ = Self._printChanges()
        VStack(alignment: .leading) {
            ProfileBanner(banner: account.banner, width: NOSTUR_SIDEBAR_WIDTH, offset: 0)
                .overlay(alignment: .bottomLeading, content: {
                    PFP(pubkey: account.publicKey, pictureUrl: account.picture, size:75, isFollowing: true)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.systemBackground, lineWidth: 3)
                        )
                        .offset(x: 10, y:37)
                })
                .overlay(alignment:.bottomTrailing) {
                    HStack(spacing: 10) {
                        Spacer()
                        FastAccountSwitcher(activePubkey: account.publicKey)
                        Button { accountsSheetIsShown = true } label: {
                            Image(systemName: "ellipsis.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                        }
                    }
                    .zIndex(20)
                    .offset(x: -10, y:37)
                }
                .zIndex(30)
            List {
                VStack(alignment: .leading) {
                    Text("\(account.display_name != "" ? account.display_name : account.name)").font(.headline)
                    Text("@\(account.name)").font(.subheadline)
                    Text(try! AttributedString(markdown: "**\(account.follows?.count ?? 0)**  Following")).font(.caption)
                }

                Button {
                    navigateTo(ContactPath(key: account.publicKey))
                    sm.showSidebar = false
                } label: {
                    Label("Profile", systemImage: "person")
                }
                Button {
                    if selectedTab != "Main" { selectedTab = "Main" }
                    navigateToOnMain(ViewPath.Lists)
                    sm.showSidebar = false
                } label: {
                    Label("Lists", systemImage: "person.2.crop.square.stack.fill")
                }
                Button {
                    selectedTab = "Bookmarks"
                    sm.showSidebar = false
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                Button {
                    if selectedTab != "Main" { selectedTab = "Main" }
                    navigateToOnMain(ViewPath.Badges)
                    sm.showSidebar = false
                } label: {
                    Label("Badges", systemImage: "medal")
                }
                Button {
                    if selectedTab != "Main" { selectedTab = "Main" }
                    navigateToOnMain(ViewPath.Settings)
                    sm.showSidebar = false
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    if selectedTab != "Main" { selectedTab = "Main" }
                    navigateToOnMain(ViewPath.Blocklist)
                    sm.showSidebar = false
                } label: {
                    Label("Block list", systemImage: "person.badge.minus")
                }
//                Button {} label: {
//                    Label("About", systemImage: "info")
//                }
                Button {
                    logoutAccount = account
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .zIndex(20)
            .listStyle(.plain)
            .padding(.top, 25)
            Spacer()
        }
        .edgesIgnoringSafeArea([.top, .leading])
        .onReceive(receiveNotification(.hideSideBar), perform: { _ in
            sm.showSidebar = false
        })
        .onReceive(receiveNotification(.showSideBar), perform: { _ in
            sm.showSidebar = true
        })
        .sheet(isPresented: $accountsSheetIsShown) {
            NavigationStack {
                AccountsSheet()
                    .presentationDetents([.fraction(0.45), .medium, .large])
                    .environmentObject(ns)
            }
        }
        .actionSheet(item: $logoutAccount) { account in
                    ActionSheet(
                        title: Text("Confirm log out"),
                        message: account.privateKey != nil
                        ? Text("""
                                 Make sure you have a back-up of your private key (nsec)
                                 Nostur cannot recover your account without it
                                 """)
                        : Text("""
                                 Account: @\(account.name) / \(account.display_name)
                                 """)
                        ,
                        buttons: account.privateKey != nil ? [
                            .destructive(Text("Log out"), action: {
                                ns.logout(account)
                                sm.showSidebar = false
                            }),
                            .default(Text("Copy private key (nsec) to clipboard"), action: {
                                if let pk = account.privateKey {
                                    UIPasteboard.general.string = nsec(pk)
                                }
                            }),
                            .cancel(Text("Cancel"))
                        ] : [
                            .destructive(Text("Log out"), action: {
                                ns.logout(account)
                                sm.showSidebar = false
                            }),
                            .cancel(Text("Cancel"))
                        ])
                }
    }
}

struct NosturRootMenu_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let account = PreviewFetcher.fetchAccount("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                
                NosturRootMenu(account: account)
            }
        }
        .withPreviewEnvironment()
    }
}
