//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI



extension NosturRootMenu {

    
    
}

struct NosturRootMenu: View {
    
    @EnvironmentObject var nav:NavigationModel
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        SideBarStack(sidebarWidth: 285, showSidebar: $nav.showSidebar) {
            if (ns.account != nil) {
                sideBar
//                    .withNavigationDestinations() TODO: Put back?
            }
        } content: {
            //TODO: Check if ns.account is loaded first
            if (ns.account != nil) {
                NosturTabsView(showMenu: $nav.showSidebar, selectedTab: $nav.selectedTab, timelinePath: $nav.timelinePath, searchPath: $nav.searchPath, accountsPath: $nav.accountsPath, bookmarksPath: $nav.bookmarksPath, notificationsPath: $nav.notificationsPath, messagesPath: $nav.messagesPath, configurationPath: $nav.configurationPath)
                    .onOpenURL { url in
                        // TODO: CHECK INPUT!!! SECURITY!
                        print(url.absoluteString)
                        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
                        if nostr.count == 1 && nostr[0].count == 4 {
                            print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
                            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
                            print("ok lets go to: \(key.hexString)")
                            if nostr[0][2] == "npub1" {                            
                                nav.navigateTo(ContactPath(key: key.hexString))
                            }
                            if nostr[0][2] == "note1" {
                                nav.navigateTo(NotePath(id: key.hexString))
                            }
                        }
                        
                        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
                        if nostur.count == 1 && nostur[0].count == 4 {
                            print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
                            if nostur[0][2] == "p:" {
                                nav.navigateTo(ContactPath(key: nostur[0][3]))
                            }
                            if nostur[0][2] == "e:" {
                                nav.navigateTo(NotePath(id: nostur[0][3]))
                            }
                        }
                        
                    }
            }
            else {
                NavigationStack(path: $nav.accountsPath) {
                    AccountListView()
                }
            }
        }
//        .edgesIgnoringSafeArea(.all)
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
                    nav.navigateTo(ContactPath(key: ns.account!.publicKey!))
                    nav.showSidebar = false
                } label: {
                    Label("Profile", systemImage: "person")
                }
                Button {} label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                Button {} label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    nav.navigateTo(ViewPath.Blocklist)
                    nav.showSidebar = false
                } label: {
                    Label("Block list", systemImage: "person.badge.minus")
                }
                Button {} label: {
                    Label("About", systemImage: "info")
                }
            }.listStyle(.plain)
            Spacer()
        }
    }

}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        NosturRootMenu()
            .withPreviewEnvironment()
    }
}
