//
//  RelaysView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI
import CoreData
import NavigationBackport
import Combine

struct RelayRowView: View {
    @Environment(\.theme) private var theme
    @ObservedObject public var relay: CloudRelay
    @ObservedObject private var cp: ConnectionPool = .shared
    
    @State private var isConnected: Bool = false
    @State private var connectedSub: AnyCancellable? = nil
    
    @State private var connection: RelayConnection? = nil
    
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
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName:"magnifyingglass.circle.fill").foregroundColor(relay.search ? theme.accent : .gray)
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
            Task {
                if let conn = await ConnectionPool.shared.getConnection(relayUrl.lowercased()) {
                    Task { @MainActor in
                        connection = conn
#if DEBUG
                        L.sockets.debug("connection is now \(connection?.url ?? "")")
#endif
                        
                        isConnected = conn.isConnected
                        connectedSub?.cancel()
                        connectedSub = conn.objectWillChange.sink { _ in
                            Task { @MainActor in
                                isConnected = conn.isConnected
                            }
                        }
                    }
                }
            }
        }
        .onReceive(cp.objectWillChange, perform: { _ in
            let relayUrl = relay.url_ ?? ""
            Task {
                if let conn = await ConnectionPool.shared.getConnection(relayUrl.lowercased()) {
                    Task { @MainActor in
                        connection = conn
#if DEBUG
                        L.sockets.debug("connection is now \(connection?.url ?? "")")
#endif
                        
                        isConnected = conn.isConnected
                        connectedSub?.cancel()
                        connectedSub = conn.objectWillChange.sink { _ in
                            Task { @MainActor in
                                isConnected = conn.isConnected
                            }
                        }
                    }
                }
            }
        })
    }
}

struct RelaysView: View {
    @Environment(\.theme) private var theme
    @State var createRelayPresented = false
    @State var editRelay: CloudRelay?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    var relays: FetchedResults<CloudRelay>

    var body: some View {
        NXForm {
            Text("These relays are used for all your accounts, and are not announced unless configured on the account specific tabs.")
            
            VStack(alignment: .leading) {
                ForEach(relays, id:\.objectID) { relay in
                    RelayRowView(relay: relay)
                        .onTapGesture {
                            editRelay = relay
                        }
                        .padding(.vertical, 5)
//                    Divider()
                }
            }
            
            Button("Add new relay...") {
                createRelayPresented = true
            }
            
        }
        .sheet(isPresented: $createRelayPresented) {
            NBNavigationStack {
                NewRelayView()
                    .presentationBackgroundCompat(theme.listBackground)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
        }
        .sheet(item: $editRelay, content: { relay in
            NBNavigationStack {
                RelayEditView(relay: relay)
                    .environment(\.theme, theme)
                    .presentationBackgroundCompat(theme.listBackground)
            }
            .nbUseNavigationStack(.never)
            
        })
        .nosturNavBgCompat(theme: theme)
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
