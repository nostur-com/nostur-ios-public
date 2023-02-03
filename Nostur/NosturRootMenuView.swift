//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

struct NosturRootMenu: View {
    
    @EnvironmentObject var ns:NosturState
    @State var showSidebar: Bool = false
    
    @State var selectedTab = "MainTimeline"
    
    @State var timelinePath = NavigationPath()
    @State var searchPath = NavigationPath()
    @State var accountsPath = NavigationPath()
    @State var bookmarksPath = NavigationPath()
    @State var notificationsPath = NavigationPath()
    @State var messagesPath = NavigationPath()
    @State var configurationPath = NavigationPath()
    
    var body: some View {
        SideBarStack(sidebarWidth: 285, showSidebar: $showSidebar) {
            if (ns.account != nil) {
                sideBar
                    .withNavigationDestinations()
            }
        } content: {
            //TODO: Check if ns.account is loaded first
            if (ns.account != nil) {
                NosturTabsView(showMenu: $showSidebar, selectedTab: $selectedTab, timelinePath: $timelinePath, searchPath: $searchPath, accountsPath: $accountsPath, bookmarksPath: $bookmarksPath, notificationsPath: $notificationsPath, messagesPath: $messagesPath, configurationPath: $configurationPath)
                    .onOpenURL { url in
                        // TODO: CHECK INPUT!!! SECURITY!
                        print(url.absoluteString)
                        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
                        if nostr.count == 1 && nostr[0].count == 4 {
                            print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
                            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
                            print("ok lets go to: \(key.hexString)")
                            if nostr[0][2] == "npub1" {                            
                                switch (selectedTab) {
                                    case "Timeline":
                                        timelinePath.append(ContactPath(key: key.hexString))
                                    case "Accounts":
                                        accountsPath.append(ContactPath(key: key.hexString))
                                    case "Bookmarks":
                                        bookmarksPath.append(ContactPath(key: key.hexString))
                                    case "Configuration":
                                        configurationPath.append(ContactPath(key: key.hexString))
                                    case "Messages":
                                        messagesPath.append(ContactPath(key: key.hexString))
                                    case "Notifications":
                                        notificationsPath.append(ContactPath(key: key.hexString))
                                    case "Search":
                                        searchPath.append(ContactPath(key: key.hexString))
                                    default:
                                        timelinePath.append(ContactPath(key: key.hexString))
                                }
                            }
                            if nostr[0][2] == "note1" {
                                switch (selectedTab) {
                                    case "Timeline":
                                        timelinePath.append(NotePath(id: key.hexString))
                                    case "Accounts":
                                        accountsPath.append(NotePath(id: key.hexString))
                                    case "Bookmarks":
                                        bookmarksPath.append(NotePath(id: key.hexString))
                                    case "Configuration":
                                        configurationPath.append(NotePath(id: key.hexString))
                                    case "Messages":
                                        messagesPath.append(NotePath(id: key.hexString))
                                    case "Notifications":
                                        notificationsPath.append(NotePath(id: key.hexString))
                                    case "Search":
                                        searchPath.append(NotePath(id: key.hexString))
                                    default:
                                        timelinePath.append(NotePath(id: key.hexString))
                                }
                            }
                        }
                        
                        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
                        if nostur.count == 1 && nostur[0].count == 4 {
                            print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
                            if nostur[0][2] == "p:" {
                                switch (selectedTab) {
                                    case "Timeline":
                                        timelinePath.append(ContactPath(key: nostur[0][3]))
                                    case "Accounts":
                                        accountsPath.append(ContactPath(key: nostur[0][3]))
                                    case "Bookmarks":
                                        bookmarksPath.append(ContactPath(key: nostur[0][3]))
                                    case "Configuration":
                                        configurationPath.append(ContactPath(key: nostur[0][3]))
                                    case "Messages":
                                        messagesPath.append(ContactPath(key: nostur[0][3]))
                                    case "Notifications":
                                        notificationsPath.append(ContactPath(key: nostur[0][3]))
                                    case "Search":
                                        searchPath.append(ContactPath(key: nostur[0][3]))
                                    default:
                                        timelinePath.append(ContactPath(key: nostur[0][3]))
                                }
                            }
                            if nostur[0][2] == "e:" {
                                switch (selectedTab) {
                                    case "Timeline":
                                        timelinePath.append(NotePath(id: nostur[0][3]))
                                    case "Accounts":
                                        accountsPath.append(NotePath(id: nostur[0][3]))
                                    case "Bookmarks":
                                        bookmarksPath.append(NotePath(id: nostur[0][3]))
                                    case "Configuration":
                                        configurationPath.append(NotePath(id: nostur[0][3]))
                                    case "Messages":
                                        messagesPath.append(NotePath(id: nostur[0][3]))
                                    case "Notifications":
                                        notificationsPath.append(NotePath(id: nostur[0][3]))
                                    case "Search":
                                        searchPath.append(NotePath(id: nostur[0][3]))
                                    default:
                                        timelinePath.append(NotePath(id: nostur[0][3]))
                                }
                            }
                        }
                        
                    }
            }
            
        }
        .edgesIgnoringSafeArea(.all)
    }
}

extension NosturRootMenu {
    
    private var sideBar: some View {
        VStack(alignment: .leading) {
            List {
                HStack {
                    ProfilePicView(pubkey: ns.account!.publicKey!, account: ns.account!)
                    Spacer()
                }
                
                Text("\(ns.account!.display_name ?? ns.account!.name)").font(.headline)
                Text("@\(ns.account!.name)").font(.subheadline)
                Text(try! AttributedString(markdown: "**bla**  Following  **196** Followers")).font(.caption)
                
                Button {
                    switch (selectedTab) {
                        case "Timeline":
                            timelinePath.append(ContactPath(key: ns.account!.publicKey!))
                        case "Accounts":
                            accountsPath.append(ContactPath(key: ns.account!.publicKey!))
                        case "Bookmarks":
                            bookmarksPath.append(ContactPath(key: ns.account!.publicKey!))
                        case "Configuration":
                            configurationPath.append(ContactPath(key: ns.account!.publicKey!))
                        case "Messages":
                            messagesPath.append(ContactPath(key: ns.account!.publicKey!))
                        case "Notifications":
                            notificationsPath.append(ContactPath(key: ns.account!.publicKey!))
                        case "Search":
                            searchPath.append(ContactPath(key: ns.account!.publicKey!))
                        default:
                            timelinePath.append(ContactPath(key: ns.account!.publicKey!))
                    }
                    showSidebar = false
                } label: {
                    Label("Profile", systemImage: "person")
                }
                Button {} label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                Button {} label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {} label: {
                    Label("About", systemImage: "info")
                }
            }.listStyle(.plain)
            Spacer()
        }
    }
    
//    func getActiveNavigationPath() -> NavigationPath {
//        switch (selectedTab) {
//            case "Timeline":
//                return timelinePath
//            case "Accounts":
//                return accountsPath
//            case "Bookmarks":
//                return bookmarksPath
//            case "Configuration":
//                return configurationPath
//            case "Messages":
//                return messagesPath
//            case "Notifications":
//                return notificationsPath
//            case "Search":
//                return searchPath
//            default:
//                return timelinePath
//        }
//    }
    
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        NosturRootMenu().withPreviewEnvironment()
    }
}
