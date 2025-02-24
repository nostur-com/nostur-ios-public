//
//  BookmarksViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2025.
//

import SwiftUI
import Combine


class NRLazyBookmark: ObservableObject, Identifiable {
    public let id: String
    public let bgEvent: Event
    @Published var nrPost: NRPost? = nil
    
    private var colorString: String? = nil
    
    public let searchableText: String
    
    init(id: String, bgEvent: Event, colorString: String? = nil) {
        self.id = id
        self.bgEvent = bgEvent
        self.colorString = colorString
        self.searchableText = (bgEvent.contact?.anyName ?? "") + " " + bgEvent.plainText // if slow, use .content?
    }
}

class BookmarksFeedModel: ObservableObject {
    
    @Published public var bookmarkFilters: Set<String> {
        didSet {
            let bookmarkFiltersStringArray = bookmarkFilters.map { $0 }
            UserDefaults.standard.set(bookmarkFiltersStringArray, forKey: "bookmark_filters")
            Task { @MainActor in
                self.load()
            }
        }
    }
    
    @Published public var isLoading = true
    @Published public var nrLazyBookmarks: [NRLazyBookmark] = []
    @Published public var searchText: String = ""
    
    public var filteredNrLazyBookmarks: [NRLazyBookmark] {
        guard !debouncedSearchText.isEmpty else { return nrLazyBookmarks }
        let tokens = debouncedSearchText.split(separator: " ")
        return nrLazyBookmarks.filter {
            // contains all tokens
            for token in tokens {
                guard !$0.searchableText.localizedCaseInsensitiveContains(token) else { continue }
                return false
            }
            return true
        }
    }
    
    private var debouncedSearchText: String = ""
    
    private var searchSubscription: AnyCancellable?
    
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        bookmarkFilters = Set<String>((UserDefaults.standard.array(forKey: "bookmark_filters") as? [String] ?? ["red", "blue", "purple", "green", "orange"]))
        
        searchSubscription = $searchText
                    .removeDuplicates()
                    .debounce(for: .seconds(0.35), scheduler: RunLoop.main)
                    .sink(receiveValue: { [weak self] value in
                        self?.objectWillChange.send()
                        self?.debouncedSearchText = value
                    })
    }
    
    @MainActor
    public func load() {
        let bookmarkFilters = self.bookmarkFilters
        let bgContext = bg()
        bgContext.perform { [weak self] in
            guard let self else { return }
            
            let r1 = Bookmark.fetchRequest()
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Bookmark.createdAt, ascending: false)]
   
            let bookmarks = ((try? bgContext.fetch(r1)) ?? [])
                .filter { bookmarkFilters.contains($0.color_ ?? "orange") }
            
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
                bgContext.delete($0)
            }
            if !duplicates.isEmpty {
                try? bgContext.save()
            }
            
            let bookmarkEventIds = bookmarks.compactMap { $0.eventId }
            
            let fr2 = Event.fetchRequest()
            fr2.predicate = NSPredicate(format: "id IN %@", bookmarkEventIds )
            let events = (try? bg().fetch(fr2)) ?? []
            let decoder = JSONDecoder()
            
            let nrLazyBookmarks = sortedBookmarks.compactMap { bookmark in
                if let event = events.first(where: { $0.id == bookmark.eventId }) {
                    return NRLazyBookmark(id: event.id, bgEvent: event, colorString: bookmark.color_)
                }
                else {
                    if let json = bookmark.json, let jsonData = json.data(using: .utf8, allowLossyConversion: false) {
                        if let nEvent = try? decoder.decode(NEvent.self, from: jsonData) {
                            let savedEvent = Event.saveEvent(event: nEvent, relays: "iCloud", context: bgContext)
                            try? bgContext.save()
                            L.cloud.debug("Decoded and saved from iCloud: \(nEvent.id) ")
                            return NRLazyBookmark(id: nEvent.id, bgEvent: savedEvent, colorString: bookmark.color_)
                        }
                    }
                    return nil
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.nrLazyBookmarks = nrLazyBookmarks
                self?.isLoading = false
            }
        }
        
    
    }
}
