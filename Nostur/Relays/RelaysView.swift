//
//  RelaysView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct RelayRowView: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject public var relay:CloudRelay
    @ObservedObject private var cp:ConnectionPool = .shared
    
    private var isConnected:Bool {
        connection?.isConnected ?? false
    }
    
    @State private var connection:RelayConnection? = nil
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        HStack {
            if (isConnected) {
                Image(systemName: "circle.fill").foregroundColor(.green)
                    .opacity(1.0)
            }
            else {
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
                    .opacity(0.2)
            }
            
            Text("\(relay.url_ ?? "(Unknown)")")
            
            Spacer()
            
            Image(systemName:"magnifyingglass.circle.fill").foregroundColor(relay.search ? themes.theme.accent : .gray)
                .opacity(relay.search ? 1.0 : 0.2)
                .onTapGesture {
                    relay.search.toggle()
                    relay.updatedAt = .now
                    connection?.relayData.setSearch(relay.search)
                    if relay.search && !isConnected {
                        connection?.connect(forceConnectionAttempt: true)
                    }
                    DataProvider.shared().save()
                }
            
            Image(systemName:"arrow.down.circle.fill").foregroundColor(relay.read ? .green : .gray)
                .opacity(relay.read ? 1.0 : 0.2)
                .onTapGesture {
                    relay.read.toggle()
                    relay.updatedAt = .now
                    connection?.relayData.setRead(relay.read)
                    if relay.read && !isConnected {
                        connection?.connect(forceConnectionAttempt: true)
                    }
                    DataProvider.shared().save()
                }
            
            Image(systemName:"arrow.up.circle.fill").foregroundColor(relay.write ? .green : .gray)
                .opacity(relay.write ? 1.0 : 0.2)
                .onTapGesture {
                    relay.write.toggle()
                    relay.updatedAt = .now
                    connection?.relayData.setWrite(relay.write)
                    DataProvider.shared().save()
                }
        }
        .task {
            let relayUrl = relay.url_ ?? ""
            connection = ConnectionPool.shared.connectionByUrl(relayUrl.lowercased())
            print("connection is now \(connection?.url ?? "")")
        }
        .onReceive(cp.objectWillChange, perform: { _ in
            let relayUrl = relay.url_ ?? ""
            connection = ConnectionPool.shared.connectionByUrl(relayUrl.lowercased())
            print("connection is now \(connection?.url ?? "")")
        })
    }
}

struct RelaysView: View {
    @EnvironmentObject private var themes: Themes
    @State var createRelayPresented = false
    @State var editRelay: CloudRelay?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    var relays: FetchedResults<CloudRelay>

    var body: some View {
        VStack {
            ForEach(relays, id:\.objectID) { relay in
                RelayRowView(relay: relay)
                    .onTapGesture {
                        editRelay = relay
                    }
                Divider()
            }            
        }
        .sheet(item: $editRelay, content: { relay in
            NBNavigationStack {
                RelayEditView(relay: relay)
            }
            .presentationBackgroundCompat(themes.theme.listBackground)
        })
        .nosturNavBgCompat(themes: themes)
    }
}

struct RelaysView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadRelays()
        }) {
            NBNavigationStack {
                RelaysView()
                    .padding()
            }
        }
    }
}
