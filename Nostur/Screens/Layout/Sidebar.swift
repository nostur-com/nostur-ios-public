//
//  Sidebar.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/09/2023.
//

import SwiftUI

final class SideBarModel: ObservableObject {
    @Published var showSidebar = false
}

struct SideBar: View {
    @EnvironmentObject private var theme:Theme
    public let sm:SideBarModel
    @ObservedObject public var account:Account
    @AppStorage("selected_tab") private var selectedTab = "Main"
    @State private var accountsSheetIsShown = false
    @State private var logoutAccount:Account? = nil
    @State private var showAnySigner = false
    
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
                                .strokeBorder(theme.background, lineWidth: 3)
                        )
                        .onTapGesture {
                            if IS_IPAD {
                                sm.showSidebar = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    navigateTo(ContactPath(key: account.publicKey))
                                }
                            }
                            else {
                                navigateTo(ContactPath(key: account.publicKey))
                                sm.showSidebar = false
                            }
                        }
                        .offset(x: 10, y: 37)
                })
                .overlay(alignment:.bottomTrailing) {
                    HStack(spacing: 10) {
                        Spacer()
                        FastAccountSwitcher(activePubkey: account.publicKey, sm: sm)
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
            List {
                Group {
                    VStack(alignment: .leading) {
                        Text("\(account.name)").font(.headline)
                        Text("**\(account.follows?.count ?? 0)**  Following", comment: "Number of people following").font(.caption)
                    }
                    
                    Button {
                        if IS_IPAD {
                            sm.showSidebar = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                navigateTo(ContactPath(key: account.publicKey))
                            }
                        }
                        else {
                            navigateTo(ContactPath(key: account.publicKey))
                            sm.showSidebar = false
                        }
                    } label: {
                        Label(String(localized:"Profile", comment:"Side bar navigation button"), systemImage: "person")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                            .contentShape(Rectangle())
                    }
                    Button {
                        if selectedTab != "Main" { selectedTab = "Main" }
                        navigateToOnMain(ViewPath.Lists)
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Feeds", comment:"Side bar navigation button"), systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                            .contentShape(Rectangle())
                    }
                    Button {
                        selectedTab = "Bookmarks"
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Bookmarks", comment:"Side bar navigation button"), systemImage: "bookmark")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                            .contentShape(Rectangle())
                    }
                    if !account.isNC {
                        Button {
                            if selectedTab != "Main" { selectedTab = "Main" }
                            navigateToOnMain(ViewPath.Badges)
                            sm.showSidebar = false
                        } label: {
                            Label(String(localized:"Badges", comment:"Side bar navigation button"), systemImage: "medal")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(theme.accent)
                                .contentShape(Rectangle())
                        }
                    }
                    Button {
                        if selectedTab != "Main" { selectedTab = "Main" }
                        navigateToOnMain(ViewPath.Settings)
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Settings", comment:"Side bar navigation button"), systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                            .contentShape(Rectangle())
                    }
                    Button {
                        if selectedTab != "Main" { selectedTab = "Main" }
                        navigateToOnMain(ViewPath.Blocklist)
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Block list", comment:"Side bar navigation button"), systemImage: "person.badge.minus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                            .contentShape(Rectangle())
                    }
                    if !account.isNC {
                        Button {
                            showAnySigner = true
                        } label: {
                            Label(String(localized:"Signer", comment:"Side bar navigation button"), systemImage: "signature")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(theme.accent)
                                .contentShape(Rectangle())
                        }
                    }
                    //                Button {} label: {
                    //                    Label(String(localized:About", comment:"Side bar navigation button"), systemImage: "info")
                    //                }
                    Button {
                        logoutAccount = account
                    } label: {
                        Label(String(localized:"Log out", comment:"Side bar navigation button"), systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                            .contentShape(Rectangle())
                    }
                }
                .listRowBackground(theme.listBackground)
            }
            .scrollContentBackground(.hidden)
            .background(theme.listBackground)
            .zIndex(20)
            .listStyle(.plain)
            .padding(.top, 45)
            Spacer()
        }
        .edgesIgnoringSafeArea(.all)
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
            }
            .presentationBackground(theme.background)
            .environmentObject(theme)
        }
        .sheet(isPresented: $showAnySigner) {
            NavigationStack {
                AnySigner()
            }
            .presentationBackground(theme.background)
            .environmentObject(theme)
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
                        NRState.shared.logout(account)
                        sm.showSidebar = false
                    }),
                    .default(Text("Copy private key (nsec) to clipboard", comment: "Button to copy private key to clipboard"), action: {
                        if let pk = account.privateKey {
                            UIPasteboard.general.string = nsec(pk)
                        }
                    }),
                    .cancel(Text("Cancel"))
                ] : [
                    .destructive(Text("Log out", comment:"Log out button"), action: {
                        NRState.shared.logout(account)
                        sm.showSidebar = false
                    }),
                    .cancel(Text("Cancel"))
                ])
        }
        .background(theme.listBackground)
    }
}
