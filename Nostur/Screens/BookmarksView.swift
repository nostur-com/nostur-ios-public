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
    
    @Binding private var navPath:NavigationPath
    @State private var bookmarks:[Bookmark] = []
    @State private var subscriptions = Set<AnyCancellable>()
    
    @ObservedObject private var settings:SettingsStore = .shared
    
    @Namespace private var top
    
    init(navPath:Binding<NavigationPath>) {
        _navPath = navPath
    }
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                if !bookmarks.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(bookmarks) { bookmark in
                            Box(nrPost: bookmark.nrPost) {
                                PostRowDeletable(nrPost: bookmark.nrPost!, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                            }
                            .id(bookmark.nrPost!.id)
                            .onDelete {
                                withAnimation {
                                    bookmarks = bookmarks.filter { $0.nrPost!.id != bookmark.nrPost!.id }
                                }
                                
                                bg().perform {
                                    bg().delete(bookmark)
                                    DataProvider.shared().bgSave()
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
        .onReceive(receiveNotification(.postAction)) { notification in
            let action = notification.object as! PostActionNotification
            if (action.type == .bookmark  && !action.bookmarked) {
                withAnimation {
                    bookmarks = bookmarks.filter { $0.nrPost!.id != action.eventId }
                }
            }
            else if action.type == .bookmark {
                self.loadBookmarks()
            }
        }
        .navigationTitle(String(localized:"Bookmarks", comment:"Navigation title for Bookmarks screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .task {
            loadBookmarks()
            listenForRemoteChanges()
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
    
    private func loadBookmarks() {
        bg().perform {
            let cloudBookmarks = Bookmark.fetchAll(context: bg())
            
            var uniqueEventIds = Set<String>()
            let sortedBookmarks = cloudBookmarks.sorted {
                ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
            }
            
            let duplicates = sortedBookmarks
                .filter { bookmark in
                    guard let eventId = bookmark.eventId else { return false }
                    return !uniqueEventIds.insert(eventId).inserted
                }
            
            duplicates.forEach { bg().delete($0) }
            
            do {
                try bg().save()
            } catch {
                print("Failed to save context: \(error)")
            }
            
            let deduplicatedBookmarks = Bookmark.fetchAll(context: bg())
            
            // check which events we have in db, else create from attached json
            
            let fr2 = Event.fetchRequest()
            fr2.predicate = NSPredicate(format: "id IN %@", deduplicatedBookmarks.compactMap { $0.eventId } )
            if let events = try? bg().fetch(fr2) {
                for event in events {
                    deduplicatedBookmarks.first(where: { $0.eventId == event.id })?.event = event
                }
            }
            
            let decoder = JSONDecoder()
            for bookmark in deduplicatedBookmarks {
                if bookmark.event == nil, let json = bookmark.json, let jsonData = json.data(using: .utf8, allowLossyConversion: false) {
                    if let nEvent = try? decoder.decode(NEvent.self, from: jsonData) {
                        let savedEvent = Event.saveEvent(event: nEvent)
                        bookmark.event = savedEvent
                    }
                }
            }
            
            let processed:[Bookmark] = deduplicatedBookmarks
                .sorted(by: { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) })
                .compactMap({ bookmark in
                    guard let event = bookmark.event else { return nil }
                    bookmark.nrPost = NRPost(event: event)
                    return bookmark
                })
            
            DispatchQueue.main.async {
                withAnimation {
                    self.bookmarks = processed
                }
            }
                
        }
    }
    
    private func listenForRemoteChanges() {
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .sink { notification in
                L.cloud.debug("Reloading bookmarks after .NSPersistentStoreRemoteChange")
                self.loadBookmarks()
            }
            .store(in: &subscriptions)
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
