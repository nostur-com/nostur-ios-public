//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct ContentView: View {
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
    
    
    var body: some View {
            TabView {
                NavigationStack {
                    TimelineView(tweets:DummyTweets().tweets())
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "house.fill")
                }
                
                Text("Notifications")
                    .badge(2)
                    .tabItem {
                        Image(systemName: "bell.fill")
                    }
                
                NavigationStack {
                    AccountsView()
                    Spacer()
                }
                .badge(0)
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }
            }
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
        ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
