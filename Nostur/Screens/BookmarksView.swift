//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI
import Combine
import CoreData

struct BookmarksView: View {
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject private var ns:NRState
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Bookmarks"
    
    @Binding var navPath:NavigationPath
    @ObservedObject private var settings:SettingsStore = .shared
    @Namespace private var top
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)])
    private var bookmarks: FetchedResults<Bookmark>
    
    @State private var events:[Event] = []
    @State private var bookmarkSnapshot: Int = 0
    @State private var noEvents = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                if !bookmarks.isEmpty && (!events.isEmpty || noEvents) {
                    LazyVStack(spacing: 10) {
                        ForEach(bookmarks) { bookmark in
                            LazyBookmark(bookmark, events: events)
                            .onDelete {
                                guard let eventId = bookmark.eventId else { return }
                                bg().perform {
                                    Bookmark.removeBookmark(eventId: eventId, context: bg())
                                    bg().transactionAuthor = "removeBookmark"
                                    DataProvider.shared().save()
                                    bg().transactionAuthor = nil
                                }
                            }
                        }
                        Spacer()
                    }
                    .background(themes.theme.listBackground)
                    .preference(key: BookmarksCountPreferenceKey.self, value: bookmarks.count.description)
                }
                else {
                    Text("When you bookmark a post it will show up here.")
                        .hCentered()
                        .padding(.top, 40)
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedSubTab == "Bookmarks" else { return }
                guard let tabName = notification.object as? String, tabName == "Bookmarks" else { return }
                if navPath.count == 0 {
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            }
        }
        .navigationTitle(String(localized:"Bookmarks", comment:"Navigation title for Bookmarks screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .onReceive(bookmarks.publisher.collect()) { bookmarks in
            let currentSnapshot = bookmarks.map(\.eventId).hashValue
            if currentSnapshot != bookmarkSnapshot {
                // Update the snapshot to the current state.
                bookmarkSnapshot = currentSnapshot
                if bookmarks.count != events.count {
                    load()
                }
            }
        }
        .simultaneousGesture(
            DragGesture().onChanged({
                if 0 < $0.translation.height {
                    sendNotification(.scrollingUp)
                }
                else if 0 > $0.translation.height {
                    sendNotification(.scrollingDown)
                }
            }))
    }
    
    private func load() {
        
        var uniqueEventIds = Set<String>()
        let sortedBookmarks = bookmarks.sorted {
            ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
        }
        
        let duplicates = sortedBookmarks
            .filter { bookmark in
                guard let eventId = bookmark.eventId else { return false }
                return !uniqueEventIds.insert(eventId).inserted
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate bookmarks")
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
            DataProvider.shared().save()
        }
        
        let bookmarkEventIds = bookmarks.compactMap { $0.eventId }
        
        bg().perform {
            let fr2 = Event.fetchRequest()
            fr2.predicate = NSPredicate(format: "id IN %@", bookmarkEventIds )
            events = (try? bg().fetch(fr2)) ?? []
            if events.count == 0 {
                noEvents = true
            }
        }
    }
}

#Preview("Bookmarks") {
    PreviewContainer({ pe in
        pe.loadPosts()
        pe.loadBookmarks()
    }) {
        VStack {
            BookmarksView(navPath: .constant(NavigationPath()))
        }
    }
}

struct LazyBookmark: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    
    private var bookmark:Bookmark
    private var events:[Event]
    
    @State private var viewState:ViewState = .loading
    @State private var nrPost:NRPost?
    
    enum ViewState {
        case loading
        case ready(NRPost)
        case error(String)
    }
    
    init(_ bookmark:Bookmark, events:[Event]) {
        self.bookmark = bookmark
        self.events = events
    }
    
    var body: some View {
        Box(nrPost: nrPost) {
            switch viewState {
            case .loading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task {
                        guard let eventId = bookmark.eventId else { viewState = .error("Cannot find post"); return }
                        let json = bookmark.json
                        bg().perform {
                            if let event = events.first(where: { $0.id == eventId }) {
                                let nrPost = NRPost(event: event)
                                DispatchQueue.main.async {
                                    self.nrPost = nrPost
                                    self.viewState = .ready(nrPost)
                                }
                            }
                            else {
                                let decoder = JSONDecoder()
                                if let json = json, let jsonData = json.data(using: .utf8, allowLossyConversion: false) {
                                    if let nEvent = try? decoder.decode(NEvent.self, from: jsonData) {
                                        let savedEvent = Event.saveEvent(event: nEvent, relays: "iCloud")
                                        let nrPost = NRPost(event: savedEvent)
                                        L.cloud.debug("Decoded and saved from iCloud: \(nEvent.id) ")
                                        DispatchQueue.main.async {
                                            self.nrPost = nrPost
                                            self.viewState = .ready(nrPost)
                                        }
                                    }
                                }
                            }
                        }
                    }
            case .ready(let nrPost):
                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
            case .error(let message):
                Text(message)
            }
        }
    }
}


struct BookmarksCountPreferenceKey: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
struct PrivateNotesCountPreferenceKey: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
