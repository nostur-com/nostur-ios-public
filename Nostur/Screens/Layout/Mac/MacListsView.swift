//
//  MacListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI

@available(iOS 16.0, *)
struct MacListsView: View {
    @EnvironmentObject private var themes:Themes
    let SIDEBAR_WIDTH:CGFloat = 50.0
    @StateObject private var dim = DIMENSIONS()
    @StateObject private var vm:MacListState = .shared
    @State var lvm:LVM? = nil
    @State var availableFeeds:[CloudFeed] = []
    
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
                            if let lvm = lvm {
                                ListViewContainer(vm: lvm)
                                    .overlay(alignment: .topTrailing) {
                                        ListUnreadCounter(vm: lvm, theme: themes.theme)
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
                    }
                }
                
                // Extra lists (+ -)
                ForEach(0..<max(1,vm.columnsCount), id:\.self) { columnIndex in
                    MacList(availableWidth: columnSize(geo.size.width)) {
                        ColumnViewWrapper(availableFeeds: availableFeeds)
                    }
                        .id(columnIndex)
                }
            }
        }
        .onAppear {
            if let account = account() {
                lvm = LVMManager.shared.followingLVM(forAccount: account)
            }
            
            availableFeeds = CloudFeed.fetchAll(context: DataProvider.shared().viewContext)
        }
        .withSheets()
        .environmentObject(dim)
        .withLightningEffect()
    }
    
    func columnSize(_ availableWidth:CGFloat) -> CGFloat {
        CGFloat((availableWidth - SIDEBAR_WIDTH)/Double(vm.columnsCount + 1))
    }
}

struct ColumnViewWrapper: View {
    let availableFeeds:[CloudFeed]
    @State private var selectedFeed:CloudFeed? = nil
    @State private var lvm:LVM? = nil
    
    var body: some View {
        ColumnView(availableFeeds: availableFeeds, selectedFeed: $selectedFeed, lvm: $lvm)
    }
}

struct ColumnView: View {
    @EnvironmentObject private var themes:Themes
    let availableFeeds:[CloudFeed]
    @Binding var selectedFeed:CloudFeed?
    @Binding var lvm:LVM?
    
    var body: some View {
        ZStack {
            themes.theme.listBackground
            VStack {
                FeedSelector(feeds: availableFeeds, selected: $selectedFeed)
                    .padding(.top, 10)
                if let lvm = lvm {
                    ListViewContainer(vm: lvm)
                        .overlay(alignment: .topTrailing) {
                            ListUnreadCounter(vm: lvm, theme: themes.theme)
                                .padding(.trailing, 10)
                                .padding(.top, 5)
                        }
                }
                Spacer()
            }
            if selectedFeed == nil {
                VStack(alignment:.leading) {
                    
                    Text("Choose content for this column")
                    
                    Group {
                        
                        Button { } label: {
                            Label("Custom Feed", systemImage: "rectangle.stack")
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
        .onChange(of: selectedFeed) { newFeed in
            if let feed = newFeed {
                lvm = LVMManager.shared.listLVM(forList: feed, isDeck: true)
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
    
    private let content: Content
    let dim:DIMENSIONS

    init(availableWidth:CGFloat = 600, @ViewBuilder content: () -> Content) {
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
            if let account = account() {
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
            
            
            Group {
                Button { addColumn() } label: {
                    Image(systemName: "rectangle.stack.fill.badge.plus")
                }
                Color.clear.frame(height: 5)
                Button { removeColumn() } label: {
                    Image(systemName: "rectangle.stack.badge.minus")
                }
            }
            Spacer()
            
            Button { SettingsStore.shared.proMode = false } label:  {
                Image(systemName: "star.fill")
            }
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

@available(iOS 16.0, *)
struct MacListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            
            pe.loadContacts()
            pe.loadNosturLists()
//            pe.loadRelayNosturLists()
            
        }, previewDevice:PreviewDevice(rawValue: "My Mac (Mac Catalyst)"), content: {
            MacListsView()
        })
    }
}
