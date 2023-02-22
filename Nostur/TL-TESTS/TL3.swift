//
//  TL3.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/02/2023.
//
 


/// 5.907 events, butter smooth scrolling is possible!

import SwiftUI
import CoreData

struct EventRow: View {
    var event:Event
    var body: some View {
        VStack(alignment:.leading) {
            HStack {
                VStack {
                    ProfilePic(event: event)
                }
                VStack {
                    NoteHeader(event: event)
                    NoteTextRenderView(event: event, useLinelimit: true)
                }
            }
            
        }
    }
}

struct TLView: View {
    @EnvironmentObject var ns:NosturState
    
    var eventsProvider: EventsProvider = .shared
    var sp: SocketPool = .shared
    var mp: MessageParser = .shared

    @AppStorage("lastUpdated")
    private var lastUpdated = Date.distantFuture.timeIntervalSince1970

    @FetchRequest(sortDescriptors: [SortDescriptor(\.created_at, order: .reverse)], predicate: NSPredicate(format: "kind IN {1,6}"))
    private var events: FetchedResults<Event>
    
    
    @State var selectedEvent:Event?
    @State private var searchText = ""
        var query: Binding<String> {
            Binding {
                searchText
            } set: { newValue in
                searchText = newValue
                events.nsPredicate = newValue.isEmpty
                                   ? nil
                : NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", ns.followingPublicKeys)
            }
        }

    var body: some View {
        
        NavigationSplitView {
            List(selection: $selectedEvent) {
                ForEach(events, id: \.id) { event in
//                    NavigationLink(destination: EventDetail(event: event)) {
                        EventRow(event: event)
//                        .onTapGesture {
//                            selectedEvent = event
//                        }
//                    }
                }
            }
            .listStyle(SidebarListStyle())
            .toolbar(content: toolbarContent)
            .refreshable {
                fetchEventsFromFollowing()
            }
            EmptyView()
        } detail: {
            if let selectedEvent {
                NoteDetail(event: selectedEvent)
            }
        }

        
//        NavigationView {
//            List {
//                ForEach(events, id: \.id) { event in
////                    NavigationLink(destination: EventDetail(event: event)) {
//                        EventRow(event: event)
////                    }
//                }
//            }
//            .listStyle(SidebarListStyle())
//            .toolbar(content: toolbarContent)
//            .refreshable {
//                fetchEventsFromFollowing()
//            }
//            EmptyView()
//        }
    }
}

// MARK: Core Data

extension TLView {
    var title: String {
        return "Posts"
    }

    private func fetchEventsFromFollowing(amount:Int? = 500) {
        lastUpdated = Date().timeIntervalSince1970
        if (ns.account?.follows != nil) {
            let pubkeys = ns.account!.follows?.map { $0.pubkey! } ?? []
            if (events.count < 20) {
                print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys 💿💿")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!)))
            }
            else {
                print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys, with since timestamp: \(d(mp.lastTimelineEventTimestamp).description) 💿💿")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!, since: mp.lastTimelineEventTimestamp)))
            }
            
        }
    }
}

// MARK: Toolbar Content

extension TLView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {

        ToolbarItemGroup(placement: .bottomBar) {
//            RefreshButton {
////                Task {
////                    await fetchEventsFromFollowing()
////                }
//                fetchEventsFromFollowing()
//            }
//            Spacer()
            Text("\(events.count) posts")
                    .foregroundStyle(Color.secondary)
                    .font(.caption)
            Spacer()
        }
    }

}

struct TLView_Previews: PreviewProvider {
    static let eventsProvider = EventsProvider.preview
    static var previews: some View {
        TLView(eventsProvider: eventsProvider)
            .environment(\.managedObjectContext,
                          eventsProvider.container.viewContext)
    }
}


struct RefreshButton: View {
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r")
    }
}
