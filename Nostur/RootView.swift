//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

struct RootView: View {
    
    @EnvironmentObject var ns:NosturState
    @State var showSidebar: Bool = false
    @State var path = NavigationPath()
    
    var body: some View {
        SideBarStack(sidebarWidth: 285, showSidebar: $showSidebar) {
            // Sidebar content here
            if (ns.account != nil) {
                VStack(alignment: .leading) {
                    List {
                        HStack {
                            ProfilePicView(pubkey: ns.account!.publicKey!, account: ns.account!)
                            Spacer()
                        }
                        
                        Text("\(ns.account!.display_name ?? "Anon")").font(.headline)
                        Text("\(ns.account!.name)").font(.subheadline)
                        Text(try! AttributedString(markdown: "**bla**  Following  **196** Followers")).font(.caption)
                        
                        Button {
                            path.append(ContactPath(key: ns.account!.publicKey!))
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
        } content: {
            // Main content here
            NavigationStack(path: $path) {
                ContentView(showMenu: $showSidebar)
            }
        }.edgesIgnoringSafeArea(.all)
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .withPreviewEnvironment()
    }
}
