//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct ContentView: View {
    
    var connectionManager: ConnectionManager
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
//    let connections = Connections.shared
    
    var body: some View {
            TabView {
                NavigationStack {
                    Button {
                        var cc = """
["REQ", "FET", {"authors": ["5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"], "kinds": [3], "limit": 1}]
"""
                        connectionManager.sendMessage(text: cc)
                    } label: {
                        Text("Test")
                    }
                    TimelineView(tweets:DummyTweets().tweets())
                    Spacer()
                }
                .tabItem { Image(systemName: "house.fill") }
                
                Text("Notifications")
                    .badge(2)
                    .tabItem { Image(systemName: "bell.fill") }
                
                NavigationStack {
                    AccountListView()
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }
                NavigationStack {
                    RelaysView()
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
    static var previews: some View {
        ContentView(connectionManager: ConnectionManager.shared)
            .environment(\.managedObjectContext,
                                PersistenceController.preview.container.viewContext)
    }
}
