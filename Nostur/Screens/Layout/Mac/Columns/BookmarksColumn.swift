//
//  BookmarksColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/11/2025.
//

import SwiftUI
import NavigationBackport

struct BookmarksColumn: View {
    @Binding var columnType: MacColumnType
    @StateObject var vm = BookmarksColumnVM()
    @Environment(\.theme) private var theme
    
    @ObservedObject private var settings: SettingsStore = .shared
    
    @State private var didLoad = false
    @State private var lastDeleted: String? = nil
    @State private var showBookmarkFilterOptions = false
    
    private var bookmarkFilters: Set<String> {
        if case .bookmarks(let filters) = columnType {
            return filters
        }
        return []
    }

    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        ScrollViewReader { proxy in
            if vm.isLoading {
                CenteredProgressView()
                    .background(theme.listBackground)
            }
            else if !vm.nrLazyBookmarks.isEmpty {
                List {
                    SearchBox(prompt: String(localized: "Search in bookmarks...", comment: "Placeholder text in bookmarks search input box"), text: $vm.searchText, autoFocus: false)
                        .id("top")
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    
                    ForEach(vm.filteredNrLazyBookmarks) { nrLazyBookmark in
                        LazyBookmark(nrLazyBookmark: nrLazyBookmark, fullWidth: settings.fullWidthImages)
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .padding(.bottom, GUTTER)
                        
                    }
                    .onDelete { indexSet in
                        deleteBookmark(section: vm.filteredNrLazyBookmarks, offsets: indexSet)
                    }
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .padding(0)
                
                .preference(key: BookmarksCountPreferenceKey.self, value: vm.nrLazyBookmarks.count.description)
            }
            else {
                Text("When you bookmark a post it will show up here.")
                    .centered()
                    .background(theme.listBackground)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            if case .bookmarks(let filters) = columnType {
                vm.load(filters: filters)
                didLoad = true
            }
        }
        
        .onChange(of: columnType) { newColumnType in
            if case .bookmarks(let filters) = columnType {
                vm.load(filters: filters)
                didLoad = true
            }
        }
        .onReceive(ViewUpdates.shared.bookmarkUpdates, perform: { update in
            if let lastDeleted, lastDeleted == update.id { // don't reload if we already removed with deleteBookmark() (swipe) or bookmark button toggle (tap)
                return
            }
            // should only reload when delete from external or different screen
            if case .bookmarks(let filters) = columnType {
                vm.load(filters: filters)
                didLoad = true
            }
        })
        
        .onReceive(receiveNotification(.postAction)) { notification in
            // Used when tapping on bookmark icon to remove
            // Removes from screen directly and doesn't do flicker reload again at db update from ViewUpdates.shared.bookmarkUpdates because
            // we set lastDeleted
            let postAction = notification.object as! PostActionNotification
            if case .bookmark(_) = postAction.type, postAction.bookmarked == false {
                // Set lastDeleted so screen doesn't flicker/reload
                lastDeleted = postAction.eventId
                withAnimation { // just update with nice animation
                    vm.nrLazyBookmarks.removeAll(where: { $0.id == postAction.eventId })
                }
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                
                HStack {
                    Text(vm.nrLazyBookmarks.count.description).lineLimit(1)
                        .font(.caption)
                        .foregroundColor(theme.accent.opacity(0.5))
                    
                    Button("Filter", systemImage: bookmarkFilters.count < BOOKMARK_COLORS.count ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                        showBookmarkFilterOptions = true
                    }
                }
            }
        }
        
        .sheet(isPresented: $showBookmarkFilterOptions, onDismiss: {
            showBookmarkFilterOptions = false
        }, content: {
            NBNavigationStack {
                ColumnBookmarkFilters(columnType: $columnType)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.background)
            .presentationDetents200()
        })
    }
    
    private func deleteBookmark(section: [NRLazyBookmark], offsets: IndexSet) {
        
        let bookmarkIdsToDelete = section.indices
            .filter { offsets.contains($0) }
            .map { section[$0] }.map { $0.id }
        
        withAnimation { // just update with nice animation
            vm.nrLazyBookmarks.removeAll(where: { bookmarkIdsToDelete.contains($0.id) })
        }
        
        // Set lastDeleted so screen doesn't flicker/reload
        for bookmarkId in bookmarkIdsToDelete {
            lastDeleted = bookmarkId
        }
        
        // Delete from db
        let bgContext = bg()
        bgContext.perform {
            for bookmarkId in bookmarkIdsToDelete {
                Bookmark.removeBookmark(eventId: bookmarkId, context: bgContext)
            }
            try? bgContext.save()
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var columnType: MacColumnType = .bookmarks([])
    BookmarksColumn(columnType: $columnType)
}

// Copy paste from BookmarkFilters, but altered to use with $columnType
struct ColumnBookmarkFilters: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var columnType: MacColumnType
    @State var onlyShow: Set<String> = Set(BOOKMARK_COLORS)
    
    var body: some View {
        VStack {
            Text("Show bookmarks")
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.brown)
                    .opacity(onlyShow.contains("brown") ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle("brown") }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.red)
                    .opacity(onlyShow.contains("red") ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle("red") }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.blue)
                    .opacity(onlyShow.contains("blue") ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle("blue") }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.purple)
                    .opacity(onlyShow.contains("purple") ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle("purple") }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.green)
                    .opacity(onlyShow.contains("green") ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle("green") }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                    .opacity(onlyShow.contains("orange") ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle("orange") }
            }
            Text("Tap to toggle")
                .font(.caption)
                .foregroundColor(.gray)
        }
        
        .onAppear {
            if case .bookmarks(let filters) = columnType {
                onlyShow = filters
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    columnType = .bookmarks(onlyShow)
                    dismiss()
                }
            }
        }
    }
    
    private func toggle(_ color: String) {
        if onlyShow.contains(color) {
            onlyShow.remove(color)
        }
        else {
            onlyShow.insert(color)
        }
    }
}

