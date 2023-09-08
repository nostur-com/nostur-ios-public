//
//  NosturRootMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import Nuke
import AVFoundation

let NOSTUR_SIDEBAR_WIDTH = 310.0

struct NosturRootMenu: View {
    let account:Account
    @StateObject private var sm = SideBarModel()
    @AppStorage("selected_tab") var selectedTab = "Main"
    
    var body: some View {
//        let _ = Self._printChanges()
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
                if 1 == 2 && IS_CATALYST {
                    MacListsView()
                        .onOpenURL { url in
                            self.handleUrl(url)
                        }
                }
                else {
                    NosturTabsView()
                        .onOpenURL { url in
                            self.handleUrl(url)
                        }
                }
            }
        }
        .environmentObject(sm)
        .onAppear {
            ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
            configureAudioSession()
        }
    }
    
    func handleUrl(_ url:URL) {
        L.og.info("handleUrl: \(url.absoluteString)")
        
        // CALLBACK FROM NWC
        if let _ = url.absoluteString.firstMatch(of: /^nostur:\/\/nwc_callback(.*)/) {
            sendNotification(.nwcCallbackReceived, AlbyCallback(url:url))
            return
        }
        
        // LINKS FROM ANYWHERE (NPUB1/NOTE1)
        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:|nostur:nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
        if nostr.count == 1 && nostr[0].count == 4 {
            L.og.info("nostr: link: \(nostr[0][2])\(nostr[0][3])")
            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
            L.og.info("nostr: link::  \(key.hexString)")
            if nostr[0][2] == "npub1" {
                navigateTo(ContactPath(key: key.hexString))
                return
            }
            if nostr[0][2] == "note1" {
                navigateTo(NotePath(id: key.hexString))
                return
            }
        }
        
        // NADDR ARTICLE
        let nostrAddr = url.absoluteString.matchingStrings(regex: "^(nostr:|nostur:nostr:)(naddr1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
        if nostrAddr.count == 1 && nostrAddr[0].count == 4 {
            L.og.info("nostr: naddr: \(nostrAddr[0][2])\(nostrAddr[0][3])")
            navigateTo(Naddr1Path(naddr1: "\(nostrAddr[0][2])\(nostrAddr[0][3])"))
            return
        }
        
        // (NEW) LINKS FROM ANYWHERE (NEVENT1/NPROFILE1)
        let nostrSharable = url.absoluteString.matchingStrings(regex: "^(nostr:|nostur:nostr:)(nevent1|nprofile1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
        if nostrSharable.count == 1 && nostrSharable[0].count == 4 {
            L.og.info("nostr: nevent1/nprofile1: \(nostrSharable[0][2])\(nostrSharable[0][3])")
            selectedTab = "Search"
            if nostrSharable[0][2] == "nevent1" {
                navigateTo(Nevent1Path(nevent1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"))
                return
            }
            if nostrSharable[0][2] == "nprofile1" {
                navigateTo(Nprofile1Path(nprofile1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"))
                return
            }
        }

        // LINKS FROM WITHIN NOSTUR
        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
        if nostur.count == 1 && nostur[0].count == 4 {
            L.og.info("nostur: link: \(nostur[0][2])\(nostur[0][3])")
            if nostur[0][2] == "p:" {
                navigateTo(ContactPath(key: nostur[0][3]))
                return
            }
            if nostur[0][2] == "e:" {
                navigateTo(NotePath(id: nostur[0][3]))
                return
            }
        }

        // LINKS FROM ANYWHERE (HEX)
        let nostrHex = url.absoluteString.matchingStrings(regex: "^(nostr:)(p:|e:)([0-9a-z]{64})$")
        if nostrHex.count == 1 && nostrHex[0].count == 4 {
            L.og.info("nostur: link: \(nostrHex[0][2])\(nostrHex[0][3])")
            if nostrHex[0][2] == "p:" {
                navigateTo(ContactPath(key: nostrHex[0][3]))
                return
            }
            if nostrHex[0][2] == "e:" {
                navigateTo(NotePath(id: nostrHex[0][3]))
                return
            }
        }

        // HASHTAG LINKS FROM WITHIN NOSTUR
        let nosturHashtag = url.absoluteString.matchingStrings(regex: "^(nostur:t:)(\\S+)$")
        if nosturHashtag.count == 1 && nosturHashtag[0].count == 3 {
            L.og.info("nostur: hashtag: \(nosturHashtag[0][2])")
            selectedTab = "Search"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                navigateTo(HashtagPath(hashTag: nosturHashtag[0][2]))
            }
            return
        }
        
        // SHARE NEW HIGHLIGHT
        if let newHighlight = url.absoluteString.firstMatch(of: /^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$/) {
            L.og.info("nostur: highlight")
            guard let url = newHighlight.output.4.removingPercentEncoding else { return }
            guard let selectedText = newHighlight.output.2.removingPercentEncoding else { return }
            let title = newHighlight.output.6.removingPercentEncoding
            sendNotification(.newHighlight, NewHighlight(url: url, selectedText: selectedText, title: title))
            return
        }
    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            L.og.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}

struct SideBar: View {
    @EnvironmentObject var theme:Theme
    let ns:NosturState = .shared
    @EnvironmentObject var sm:SideBarModel
    @ObservedObject var account:Account
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var accountsSheetIsShown = false
    @State var logoutAccount:Account? = nil
    @State var showAnySigner = false
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(alignment: .leading) {
            ProfileBanner(banner: account.banner, width: NOSTUR_SIDEBAR_WIDTH, offset: 0)
                .overlay(alignment: .bottomLeading, content: {
                    PFP(pubkey: account.publicKey, account: account, size:75)
                        .overlay(
                            Circle()
                                .strokeBorder(theme.background, lineWidth: 3)
                        )
                        .offset(x: 10, y:37)
                        .onTapGesture {
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
                        }
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
                                .foregroundColor(theme.accent)
                        }
                    }
                    .zIndex(20)
                    .offset(x: -10, y:37)
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
                    }
                    Button {
                        if selectedTab != "Main" { selectedTab = "Main" }
                        navigateToOnMain(ViewPath.Lists)
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Feeds", comment:"Side bar navigation button"), systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                    }
                    Button {
                        selectedTab = "Bookmarks"
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Bookmarks", comment:"Side bar navigation button"), systemImage: "bookmark")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
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
                    }
                    Button {
                        if selectedTab != "Main" { selectedTab = "Main" }
                        navigateToOnMain(ViewPath.Blocklist)
                        sm.showSidebar = false
                    } label: {
                        Label(String(localized:"Block list", comment:"Side bar navigation button"), systemImage: "person.badge.minus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(theme.accent)
                    }
                    if !account.isNC {
                        Button {
                            showAnySigner = true
                        } label: {
                            Label(String(localized:"Signer", comment:"Side bar navigation button"), systemImage: "signature")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(theme.accent)
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
            .presentationBackground(theme.background)
        }
        .sheet(isPresented: $showAnySigner) {
            NavigationStack {
                AnySigner()
                    .environmentObject(ns)
            }
            .presentationBackground(theme.background)
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
                                ns.logout(account)
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
                                ns.logout(account)
                                sm.showSidebar = false
                            }),
                            .cancel(Text("Cancel"))
                        ])
                }
        .background(theme.listBackground)
    }
}

struct NosturRootMenu_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                if let account = PreviewFetcher.fetchAccount("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    
                    NosturRootMenu(account: account)
                }
            }
            .onAppear {
                Theme.default.loadRed()
            }
        }
    }
}
