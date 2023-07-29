//
//  MacListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI

struct MacListsView: View {
    let SIDEBAR_WIDTH:CGFloat = 50.0
    @StateObject private var dim = DIMENSIONS()
    @StateObject private var vm:MacListState = .shared
    @StateObject private var followingVM:FollowingViewModel = .main
    
    var body: some View {
//        let _ = Self._printChanges()
        GeometryReader { geo in
            HStack {
                // Tabs on the side
                SideTabs(columnsCount: $vm.columnsCount, selectedTab: $vm.selectedTab)
                    .frame(width: SIDEBAR_WIDTH)
                
                // Main list (following/notifications/bookmarks)
                MacList(availableWidth: columnSize(geo.size.width)) {
                    TabView(selection: $vm.selectedTab) {
                        VStack(spacing:0) {
                            MacListHeader(title: String(localized:"Following"))
                            if let vm = followingVM.activeVM {
                                ListViewContainer(vm: vm)
                                    .overlay(alignment: .topTrailing) {
                                        ListUnreadCounter(vm: vm)
                                            .padding(.trailing, 10)
                                            .padding(.top, 5)
                                    }
                            }
                        }
                            .tag("Main")
                            .toolbar(.hidden, for: .tabBar)
                        
                        NotificationsContainer()
                            .tag("Notifications")
                            .toolbar(.hidden, for: .tabBar)

                        Search()
                            .tag("Search")
                            .toolbar(.hidden, for: .tabBar)
                        
                        BookmarksAndPrivateNotes()
                            .tag("Bookmarks")
                            .toolbar(.hidden, for: .tabBar)
                        
                        DirectMessagesContainer()
                            .tag("Messages")
                            .toolbar(.hidden, for: .tabBar)
                    }
                }
                
                // Extra lists (+ -)
                ForEach(0..<max(1,vm.columnsCount), id:\.self) { columnIndex in
                    MacList(availableWidth: columnSize(geo.size.width)) {
                        SomeView()
                    }
                        .id(columnIndex)
                }
            }
        }
        .onAppear {
            followingVM.account = NosturState.shared.account
        }
        .withSheets()
        .environmentObject(dim)
        .withLightningEffect()
    }
    
    func columnSize(_ availableWidth:CGFloat) -> CGFloat {
        CGFloat((availableWidth - SIDEBAR_WIDTH)/Double(vm.columnsCount + 1))
    }
}

struct SomeView: View {
    var body: some View {
        ZStack {
            Color("ListBackground")
            VStack(alignment:.leading) {
                Text("Choose content for this column")
                
                Group {
                    Button { } label: {
                        Label("Custom Feed", systemImage: "person.3.fill")
                    }
                    
                    Button { } label: {
                        Label("Profile", systemImage: "person.fill")
                    }
                    
                    Button { } label: {
                        Label("Private notes", systemImage: "note.text")
                    }
                    
                    Button { } label: {
                        Label("Hashtag", systemImage: "number")
                    }
                    
                    Button { } label: {
                        Label("Messages", systemImage: "envelope")
                    }
                    
                    Button { } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct MacListHeader: View {
    var title:String? = nil
    
    var body: some View {
        
        TabButton(action: {
            
        }, title: title ?? "List")
    }
}


struct MacList<Content: View>: View {
    
    let content: Content
    let dim:DIMENSIONS

    init(availableWidth:CGFloat = 600, @ViewBuilder content: ()->Content) {
        self.content = content()
        self.dim = DIMENSIONS()
        self.dim.listWidth = CGFloat(availableWidth)
    }
    
    var body: some View {
        content
            .environmentObject(dim)
    }
}


struct SideTabs:View {
    @Binding var columnsCount:Int
    @Binding var selectedTab:String
    
    var body: some View {
        VStack {
            if let account = NosturState.shared.account {
                PFP(pubkey: account.publicKey, account: account, size:30)
                    .padding(10)
            }
            
            Button { selectedTab = "Main" } label: {
                Image(systemName: "house")
                    .accessibilityLabel("Following")
                    .padding(10)
                    .contentShape(Rectangle())
            }
            
            Button { selectedTab = "Notifications" } label: {
                Image(systemName: "bell.fill")
                    .accessibilityLabel("Notifications")
                    .padding(10)
                    .contentShape(Rectangle())
            }
            
            Button { selectedTab = "Search" } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("Search")
                    .padding(10)
                    .contentShape(Rectangle())
            }
            
            Button { selectedTab = "Bookmarks" } label: {
                Image(systemName:"bookmark")
                    .accessibilityLabel("Bookmarks")
                    .padding(10)
                    .contentShape(Rectangle())
            }
            
            Button { selectedTab = "Messages" } label: {
                Image(systemName:"envelope.fill")
                    .accessibilityLabel("Messages")
                    .padding(10)
                    .contentShape(Rectangle())
            }
            
            Spacer()
            
            
            Button { addColumn() } label: {
                Image(systemName: "rectangle.righthalf.inset.fill.arrow.right")
            }
            Button { removeColumn() } label: {
                Image(systemName: "rectangle.lefthalf.inset.fill.arrow.left")
            }
            Spacer()
        }
//        .padding(.top, 100)
    }
    
    func addColumn() {
        guard columnsCount < 10 else { return }
        columnsCount += 1
    }
    
    func removeColumn() {
        guard columnsCount > 1 else { return }
        columnsCount -= 1
    }
}

struct MacListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer(previewDevice:PreviewDevice(rawValue: "My Mac (Mac Catalyst)")) {
            MacListsView()
        }
    }
}
