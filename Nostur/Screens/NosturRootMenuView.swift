//
//  NosturRootMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

struct NosturRootMenu: View {
    let account:Account
    @StateObject private var sm = SideBarModel()
    
    var body: some View {
        let _ = Self._printChanges()
        SideBarStack(sidebarWidth: 310) {
            SideBar(account: account)
        } content: {
            NosturTabsView()
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
            List {
                HStack(spacing: 10) {
                    PFP(pubkey: account.publicKey, pictureUrl: account.picture)
                    Spacer()
                    FastAccountSwitcher()
                    Button { accountsSheetIsShown = true } label: {
                        Image(systemName: "ellipsis.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                    }
//                    .buttonStyle(.bordered)
//                    .buttonBorderShape(.capsule)
                }

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
//                Button {
//                    if selectedTab != "Main" { selectedTab = "Main" }
//                    navigateToOnMain(ViewPath.Lists)
//                    sm.showSidebar = false
//                } label: {
//                    Label("Lists", systemImage: "person.2.crop.square.stack.fill")
//                }
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
            .listStyle(.plain)
            Spacer()
        }
        .sheet(isPresented: $accountsSheetIsShown) {
            NavigationStack {
                AccountsSheet()
                    .presentationDetents([.fraction(0.45), .medium, .large])
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
        let account = PreviewFetcher.fetchAccount()!
        NosturRootMenu(account: account)
            .withPreviewEnvironment()
    }
}
