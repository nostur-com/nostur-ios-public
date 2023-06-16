import SwiftUI

struct NosturTabsView: View {
    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var unread = 0
    @State var unreadDMs = 0
    
    var body: some View {
//        let _ = Self._printChanges()
        HStack {
            VStack {
                Color.clear.frame(height: 0)
                    .modifier(SizeModifier())
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        guard size.width > 0 else { return }
                        dim.listWidth = size.width
                    }
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
                }
                .withSheets()
            }
            .frame(maxWidth: 600)
            .environmentObject(dim)
            .edgesIgnoringSafeArea(.all)
            if UIDevice.current.userInterfaceIdiom == .pad {
                DetailPane()
            }
        }
        .background(Color("ListBackground"))
        .withLightningEffect()
        .onChange(of: selectedTab) { newValue in
            if newValue == "Notifications" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    sendNotification(.notificationsTabAppeared) // use for resetting unread count
                }
            }
        }
        .onReceive(receiveNotification(.updateNotificationsCount)) { notification in
            unread = (notification.object as! Int)
        }
        .onReceive(receiveNotification(.updateDMsCount)) { notification in
            unreadDMs = (notification.object as! Int)
        }
    }
}
