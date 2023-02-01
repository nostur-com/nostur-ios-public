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
    @State var sidebarPath = NavigationPath()
    
    var body: some View {
        SideBarStack(sidebarWidth: 285, showSidebar: $showSidebar) {
            if (ns.account != nil) {
                NavigationStack(path: $sidebarPath) {
                    sideBar
                        .withNavigationDestinations()
                }
            }
        } content: {
            NosturTabsView(showMenu: $showSidebar, selectedTab: $selectedTab)
                .onOpenURL { url in
                    // TODO: CHECK INPUT!!! SECURITY!
                    print(url.absoluteString)
                    let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
                    if nostr.count == 1 && nostr[0].count == 4 {
                        print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
                        let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
                        print("ok lets go to: \(key.hexString)")
                        if nostr[0][2] == "npub1" {
                            sidebarPath.append(ContactPath(key: key.hexString))
                        }
                        if nostr[0][2] == "note1" {
                            sidebarPath.append(NotePath(id: key.hexString))
                        }
                    }
                    
                    let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
                    if nostur.count == 1 && nostur[0].count == 4 {
                        print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
                        if nostur[0][2] == "p:" {
                            sidebarPath.append(ContactPath(key: nostur[0][3]))
                        }
                        if nostur[0][2] == "e:" {
                            sidebarPath.append(NotePath(id: nostur[0][3]))
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
                    sidebarPath.append(ContactPath(key: ns.account!.publicKey!))
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
    
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        NosturRootMenu().withPreviewEnvironment()
    }
}
