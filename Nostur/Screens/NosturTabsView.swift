//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
import Nuke

struct NosturTabsView: View {
    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var unread = 0
    @State var unreadDMs = 0
    
    var body: some View {
        let _ = Self._printChanges()
        HStack {
            VStack {
                Color.clear.frame(height: 0)
                    .modifier(SizeModifier())
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        guard size.width > 0 else { return }
                        dim.listWidth = size.width
                        print("🟣🟣🟣🟣🟣 NEW WIDTH \(size.width) -- Scale: \(UIScreen.main.scale) ")
                    }
                AppTopBar()
                    .padding(5)
                TabView(selection: $selectedTab) {
                    MainView()
                        .tabItem { Image(systemName: "house") }
                        .tag("Main")
                    
                    NotificationsContainer()
                        .tabItem { Image(systemName: "bell.fill") }
                        .tag("Notifications")
                        .badge(unread)
                    
                    Search()
                        .tabItem { Image(systemName: "magnifyingglass") }
                        .tag("Search")
                    
                    
                    BookmarksAndPrivateNotes()
                        .tabItem { Image(systemName: "bookmark") }
                        .tag("Bookmarks")
                    
                    DirectMessagesContainer()
                        .tabItem { Image(systemName: "envelope.fill") }
                        .tag("Messages")
                        .badge(unreadDMs)
                    
                    
                    //                    ConfigurationView() // TODO: MOVE TO SETTINGS
                    //                    .tabItem { Image(systemName: "server.rack") }
                    //                    .tag("Configuration")
                }
                .withSheets()
            }
            .frame(maxWidth: 600)
            .environmentObject(dim)
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabbedDetailContainer()
            }
        }
        .onOpenURL { url in
            self.handleUrl(url)
        }
        .onReceive(receiveNotification(.updateNotificationsCount)) { notification in
            unread = (notification.object as! Int)
        }
        .onReceive(receiveNotification(.updateDMsCount)) { notification in
            unreadDMs = (notification.object as! Int)
        }
        .onAppear {
            ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        }
    }
    
}

extension NosturTabsView {
    func handleUrl(_ url:URL) {
        // TODO: CHECK INPUT!!! SECURITY!
        print(url.absoluteString)
        // LINKS FROM ANYWHERE (NPUB1/NOTE1)
        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
        if nostr.count == 1 && nostr[0].count == 4 {
            print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
            print("ok lets go to: \(key.hexString)")
            if nostr[0][2] == "npub1" {
                navigateTo(ContactPath(key: key.hexString))
            }
            if nostr[0][2] == "note1" {
                navigateTo(NotePath(id: key.hexString))
            }
        }

        // LINKS FROM WITHIN NOSTUR
        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
        if nostur.count == 1 && nostur[0].count == 4 {
            print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
            if nostur[0][2] == "p:" {
                navigateTo(ContactPath(key: nostur[0][3]))
            }
            if nostur[0][2] == "e:" {
                navigateTo(NotePath(id: nostur[0][3]))
            }
        }

        // LINKS FROM ANYWHERE (HEX)
        let nostrHex = url.absoluteString.matchingStrings(regex: "^(nostr:)(p:|e:)([0-9a-z]{64})$")
        if nostrHex.count == 1 && nostrHex[0].count == 4 {
            print("ok lets go to: \(nostrHex[0][2])\(nostrHex[0][3])")
            if nostrHex[0][2] == "p:" {
                navigateTo(ContactPath(key: nostrHex[0][3]))
            }
            if nostrHex[0][2] == "e:" {
                navigateTo(NotePath(id: nostrHex[0][3]))
            }
        }

        // HASHTAG LINKS FROM WITHIN NOSTUR
        let nosturHashtag = url.absoluteString.matchingStrings(regex: "^(nostur:t:)(\\S+)$")
        if nosturHashtag.count == 1 && nosturHashtag[0].count == 3 {
            print("ok lets go to: \(nosturHashtag[0][2])")
            selectedTab = "Search"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                navigateTo(HashtagPath(hashTag: nosturHashtag[0][2]))
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    //    @State static var showMenu = false
    //    @State static var selectedTab = "Timeline"
    //
    //    @State static var timelinePath = NavigationPath()
    //    @State static var searchPath = NavigationPath()
    //    @State static var accountsPath = NavigationPath()
    //    @State static var bookmarksPath = NavigationPath()
    //    @State static var notificationsPath = NavigationPath()
    //    @State static var messagesPath = NavigationPath()
    //    @State static var configurationPath = NavigationPath()
    //    @State static var detailPath = NavigationPath()
    //    @State static var showSidebar = false
    
    static var previews: some View {
        NosturTabsView()
            .withPreviewEnvironment()
    }
}
