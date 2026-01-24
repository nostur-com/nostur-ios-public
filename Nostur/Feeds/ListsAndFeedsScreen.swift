//
//  ListsAndFeedsScreen.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//

import SwiftUI
import NavigationBackport

struct ListsAndFeedsScreen: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\CloudFeed.order, order: .forward)], predicate: NSPredicate(format: "NOT type IN %@ OR type = nil", ["following", "picture", "yak", "vine"]))
    var lists: FetchedResults<CloudFeed>

    @State var newContactsFeedSheet = false
    @State var newRelayFeedSheet = false
    @State private var didRemoveDuplicates = false
    
    @AppStorage("enable_zapped_feed") private var enableZappedFeed: Bool = true
    @AppStorage("enable_hot_feed") private var enableHotFeed: Bool = true
    @AppStorage("enable_picture_feed") private var enablePictureFeed: Bool = true
    @AppStorage("enable_yak_feed") private var enableYakFeed: Bool = true
    @AppStorage("enable_vine_feed") private var enableVineFeed: Bool = true
    @AppStorage("enable_emoji_feed") private var enableEmojiFeed: Bool = true
    @AppStorage("enable_discover_feed") private var enableDiscoverFeed: Bool = true
    @AppStorage("enable_discover_lists_feed") private var enableDiscoverListsFeed: Bool = true
    @AppStorage("enable_streams_feed") private var enableStreamsFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true
        
    var body: some View {
        NXForm {
            if !lists.isEmpty {
                Section("Custom Feeds") {
                    ForEach(lists) { list in
                        NavigationLink {
                            FeedSettings(feed: list)
                                .environment(\.containerID, "Default") // Should be Default right?
                        } label: {
                            ListRow(list: list)
                        }
                    }
                    .onDelete { indexSet in
                        deleteList(section: Array(lists), offsets: indexSet)
                    }
                    .onMove(perform: { indices, newOffset in
                            var s = lists.sorted(by: { $0.order < $1.order })
                            s.move(fromOffsets: indices, toOffset: newOffset)
                            for (index, item) in s.enumerated() {
                                item.order = Int16(index)
                            }
                            DataProvider.shared().saveToDiskNow(.viewContext)
                     })
                }
            }
            
            Section {
                Toggle(isOn: $enablePictureFeed, label: {
                    Text("Pictures")
                    Text("Pictures-only feed from people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableYakFeed, label: {
                    Text("Yaks")
                    Text("Voice Messages feed from people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableVineFeed, label: {
                    Text("diVines")
                    Text("Short videos feed from people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableZappedFeed, label: {
                    Text("Zapped")
                    Text("Posts from anyone which are most zapped by people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableHotFeed, label: {
                    Text("Hot")
                    Text("Posts from anyone which are most liked or reposted by people you follow")
                        .foregroundStyle(.secondary)
                })
//                    Toggle(isOn: $enableDiscoverFeed, label: {
//                        Text("Discover")
//                        Text("Posts from people you don't follow which are most liked or reposted by people you follow").font(.footnote)
//                .foregroundStyle(.secondary)
//                    })
                Toggle(isOn: $enableDiscoverListsFeed, label: {
                    Text("Follow Packs & Lists")
                    Text("Lists created by people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableStreamsFeed, label: {
                    Text("Live Streams")
                    Text("Live Streams from people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableEmojiFeed, label: {
                    Text("Funny Feed")
                    Text("Posts from anyone reacted to by people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableGalleryFeed, label: {
                    Text("Gallery")
                    Text("Media from posts from anyone which are most liked or reposted by people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableArticleFeed, label: {
                    Text("Reads")
                    Text("Long-form articles from people you follow")
                        .foregroundStyle(.secondary)
                })
                Toggle(isOn: $enableExploreFeed, label: {
                    Text("Explore")
                    Text("Posts from people followed by the [Explore Feed](nostur:p:afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320) account")
                        .foregroundStyle(.secondary)
                })
            } header: {
                Text("Default feeds")
            } footer: {
                Text("Picture-only, Yaks, diVines, Hot, Discover, Gallery, and Articles feed will not be visible if you don't follow more than 10 people.")
                    .foregroundStyle(.secondary)
            }
        }
//        .scrollContentBackgroundCompat(.hidden)
        
        .navigationTitle(String(localized:"Feeds", comment: "Navigation title for Feeds screen"))
        .navigationBarTitleDisplayMode(.inline)
        
        .sheet(isPresented: $newContactsFeedSheet) {
            NBNavigationStack {
                NewContactsFeedSheet(rootDismiss: { dismiss() })
                    .environment(\.theme, theme)
                    .environmentObject(la)
            }
            .presentationBackgroundCompat(theme.listBackground)
        }
        
        .sheet(isPresented: $newRelayFeedSheet) {
            NBNavigationStack {
                NewRelayFeedSheet(rootDismiss: { dismiss() })
                    .environment(\.theme, theme)
                    .environmentObject(la)
            }
            .presentationBackgroundCompat(theme.listBackground)
        }
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        newRelayFeedSheet = true
                    }) {
                        Label("New relay feed", systemImage: "server.rack")
                    }
                    
                    Button(action: {
                        newContactsFeedSheet = true
                    }) {
                        Label("New contacts list feed", systemImage: "person.3")
                    }

                } label: {
                    Label("New Feed", systemImage: "plus")
                }
                .help("New Feed...")
            }
        }
        
//         .nosturNavBgCompat(theme: theme)
    }
    
    private func deleteList(section: [CloudFeed], offsets: IndexSet) {
        for index in offsets {
            let item = section[index]
            viewContext.delete(item)
        }
        DataProvider.shared().saveToDiskNow(.viewContext)
        if IS_DESKTOP_COLUMNS() {
            Task {
                await MacColumnsVM.shared.load()
            }
        }
    }
    
    private func removeDuplicateLists() {
        var uniqueLists = Set<String>()
        let sortedLists = lists.sorted {
            if ($0.showAsTab && !$1.showAsTab) { return true }
            else {
                return ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
            }
        }
        
        let toDelete = sortedLists
            .filter { list in
                guard let id = list.id else { return true }
                return !uniqueLists.insert(id.uuidString).inserted
            }
        
        toDelete.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !toDelete.isEmpty {
#if DEBUG
            L.cloud.debug("Deleting: \(toDelete.count) duplicate feeds")
#endif
            DataProvider.shared().saveToDiskNow(.viewContext)
            didRemoveDuplicates = true
        }
    }
}

struct ListRow: View {
    @ObservedObject var list: CloudFeed
    let showPin: Bool
    
    init(list: CloudFeed, showPin: Bool = true) {
        self.list = list
        self.showPin = showPin
    }
    
    var body: some View {
        HStack {
            if showPin {
                Image(systemName: list.showAsTab ? "pin.fill" : "pin")
            }
            Text(list.name_)
            Spacer()
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadCloudFeeds()
    }) {
        NBNavigationStack {
            ListsAndFeedsScreen()
        }
    }
}
