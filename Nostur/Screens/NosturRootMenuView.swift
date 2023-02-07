//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI



extension NosturRootMenu {

    @MainActor class NosturRootMenuViewModel: ObservableObject {
        @Published var showSidebar: Bool = false
        @Published var selectedTab = "Timeline"
        @Published var timelinePath = NavigationPath()
        @Published var searchPath = NavigationPath()
        @Published var accountsPath = NavigationPath()
        @Published var bookmarksPath = NavigationPath()
        @Published var notificationsPath = NavigationPath()
        @Published var messagesPath = NavigationPath()
        @Published var configurationPath = NavigationPath()
        
        func navigateTo(_ path:any Hashable) -> Void {
            switch (selectedTab) {
                case "Timeline":
                    self.timelinePath.append(path)
                case "Accounts":
                    self.accountsPath.append(path)
                case "Bookmarks":
                    self.bookmarksPath.append(path)
                case "Configuration":
                    self.configurationPath.append(path)
                case "Messages":
                    self.messagesPath.append(path)
                case "Notifications":
                    self.notificationsPath.append(path)
                case "Search":
                    self.searchPath.append(path)
                default:
                    self.timelinePath.append(path)
            }
        }
    }
    
}

struct NosturRootMenu: View {
    
    @EnvironmentObject var ns:NosturState
    @StateObject var vm = NosturRootMenuViewModel()
    
    var body: some View {
        SideBarStack(sidebarWidth: 285, showSidebar: $vm.showSidebar) {
            if (ns.account != nil) {
                sideBar
                    .withNavigationDestinations()
            }
        } content: {
            //TODO: Check if ns.account is loaded first
            if (ns.account != nil) {
                NosturTabsView(showMenu: $vm.showSidebar, selectedTab: $vm.selectedTab, timelinePath: $vm.timelinePath, searchPath: $vm.searchPath, accountsPath: $vm.accountsPath, bookmarksPath: $vm.bookmarksPath, notificationsPath: $vm.notificationsPath, messagesPath: $vm.messagesPath, configurationPath: $vm.configurationPath)
                    .onOpenURL { url in
                        // TODO: CHECK INPUT!!! SECURITY!
                        print(url.absoluteString)
                        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
                        if nostr.count == 1 && nostr[0].count == 4 {
                            print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
                            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
                            print("ok lets go to: \(key.hexString)")
                            if nostr[0][2] == "npub1" {                            
                                vm.navigateTo(ContactPath(key: key.hexString))
                            }
                            if nostr[0][2] == "note1" {
                                vm.navigateTo(NotePath(id: key.hexString))
                            }
                        }
                        
                        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
                        if nostur.count == 1 && nostur[0].count == 4 {
                            print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
                            if nostur[0][2] == "p:" {
                                vm.navigateTo(ContactPath(key: nostur[0][3]))
                            }
                            if nostur[0][2] == "e:" {
                                vm.navigateTo(NotePath(id: nostur[0][3]))
                            }
                        }
                        
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
                    vm.navigateTo(ContactPath(key: ns.account!.publicKey!))
                    vm.showSidebar = false
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
                    vm.navigateTo(ViewPath.Blocklist)
                    vm.showSidebar = false
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
