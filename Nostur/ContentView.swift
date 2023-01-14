//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct ContentView: View {
    
    var cloudContainer:NSPersistentCloudKitContainer
    var connectionManager: ConnectionManager
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
//    let connections = Connections.shared
    
    var body: some View {
            TabView {
                NavigationStack {
                    TestTimeline(cloudContainer: cloudContainer)
                }
                .tabItem { Image(systemName: "figure.fall") }
                NavigationStack {
                    Playground(cloudContainer:cloudContainer)
//                        .environment(\.managedObjectContext,
//                                      PersistenceController.shared.localContainer.viewContext)
                }
                .tabItem { Image(systemName: "lightbulb.fill") }
                NavigationStack {
                    TimelineView(tweets:DummyTweets().tweets())
                    Spacer()
                }
                .tabItem { Image(systemName: "house.fill") }
                
                Text("Notifications")
                    .badge(2)
                    .tabItem { Image(systemName: "bell.fill") }
                
                NavigationStack {
                    AccountListView()
                        .environment(\.managedObjectContext,
                                      PersistenceController.shared.cloudContainer.viewContext)
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }
                NavigationStack {
                    RelaysView()
                        .environment(\.managedObjectContext,
                                      PersistenceController.shared.cloudContainer.viewContext)
                    Spacer()
                }
                .tabItem { Image(systemName: "server.rack") }
            }
            .onAppear { print("🔴 OnAppear") }
            .onDisappear { print("🔴 OnDisappear") }
    }
    
    
    
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    static var cloudContainer = PersistenceController.preview.cloudContainer

    static var previews: some View {
        ContentView(cloudContainer:cloudContainer, connectionManager: ConnectionManager.shared)
            .environment(\.managedObjectContext,
                                PersistenceController.preview.localContainer.viewContext)
    }
}

//struct ContentView_Previews: PreviewProvider {
//
//    static var previews: some View {
//        ContentView(connectionManager: ConnectionManager.shared)
//            .environment(\.managedObjectContext,
//                                PersistenceController.preview.container.viewContext)
//    }
//}
