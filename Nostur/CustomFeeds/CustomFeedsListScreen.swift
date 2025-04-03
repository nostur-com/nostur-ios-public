//
//  NosturListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//

import SwiftUI
import NavigationBackport

struct CustomFeedsListScreen: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\CloudFeed.createdAt, order: .reverse)], predicate: NSPredicate(format: "NOT type IN %@ OR type = nil", ["following", "picture"]))
    var lists: FetchedResults<CloudFeed>

    @State var newListSheet = false
    @State private var didRemoveDuplicates = false
    
    @AppStorage("enable_zapped_feed") private var enableZappedFeed: Bool = true
    @AppStorage("enable_hot_feed") private var enableHotFeed: Bool = true
    @AppStorage("enable_picture_feed") private var enablePictureFeed: Bool = true
    @AppStorage("enable_emoji_feed") private var enableEmojiFeed: Bool = true
    @AppStorage("enable_discover_feed") private var enableDiscoverFeed: Bool = true
    @AppStorage("enable_discover_lists_feed") private var enableDiscoverListsFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true
        
    var body: some View {
        List {
            if !lists.isEmpty {
                Section {
                    ForEach(lists) { list in
                        NBNavigationLink(value: list) {
                            ListRow(list: list)
                        }
                        .listRowBackground(themes.theme.background)
                    }
                    .onDelete { indexSet in
                        deleteList(section: Array(lists), offsets: indexSet)
                    }
                } header: {
                    Text("Custom Feeds")
                }
                .listRowBackground(themes.theme.listBackground)
            }
            
            Section {
                Group {
                    Toggle(isOn: $enablePictureFeed, label: {
                        Text("Pictures")
                        Text("Pictures-only feed from people you follow")
                    })
                    Toggle(isOn: $enableZappedFeed, label: {
                        Text("Zapped")
                        Text("Posts from anyone which are most zapped by people you follow")
                    })
                    Toggle(isOn: $enableHotFeed, label: {
                        Text("Hot")
                        Text("Posts from anyone which are most liked or reposted by people you follow")
                    })
//                    Toggle(isOn: $enableDiscoverFeed, label: {
//                        Text("Discover")
//                        Text("Posts from people you don't follow which are most liked or reposted by people you follow")
//                    })
                    Toggle(isOn: $enableDiscoverListsFeed, label: {
                        Text("Discover")
                        Text("Lists from people follow")
                    })
                    Toggle(isOn: $enableEmojiFeed, label: {
                        Text("Emoji Feed")
                        Text("Posts from anyone which are reacted to with several specific emojis by people you follow")
                    })
                    Toggle(isOn: $enableGalleryFeed, label: {
                        Text("Gallery")
                        Text("Media from posts from anyone which are most liked or reposted by people you follow")
                    })
                    Toggle(isOn: $enableArticleFeed, label: {
                        Text("Articles")
                        Text("Long-form articles from people you follow")
                    })
                    Toggle(isOn: $enableExploreFeed, label: {
                        Text("Explore")
                        Text("Posts from people followed by the [Explore Feed](nostur:p:afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320) account")
                    })
                }
                .listRowBackground(themes.theme.background)
            } header: {
                Text("Default feeds")
            } footer: {
                Text("Picture-only, Hot, Discover, Gallery, and Articles feed will not be visible if you don't follow more than 10 people.")
                    .font(.footnote)
            }
            .listRowBackground(themes.theme.listBackground)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(themes.theme.listBackground)
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    newListSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(String(localized:"Create new feed", comment: "Button to create a new feed"))
            }
        }
        .navigationTitle(String(localized:"Feeds", comment: "Navigation title for Feeds screen"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $newListSheet) {
            NBNavigationStack {
                NewListSheet()
                    .environmentObject(themes)
            }
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .nosturNavBgCompat(themes: themes)
    }
    
    private func deleteList(section: [CloudFeed], offsets: IndexSet) {
        for index in offsets {
            let item = section[index]
            viewContext.delete(item)
        }
        viewContextSave()
    }
    
    func removeDuplicateLists() {
        var uniqueLists = Set<String>()
        let sortedLists = lists.sorted {
            if ($0.showAsTab && !$1.showAsTab) { return true }
            else {
                return ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
            }
        }
        
        let duplicates = sortedLists
            .filter { list in
                guard let id = list.id else { return false }
                return !uniqueLists.insert(id.uuidString).inserted
            }
        
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !duplicates.isEmpty {
            L.cloud.debug("Deleting: \(duplicates.count) duplicate feeds")
            DataProvider.shared().save()
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

struct NosturListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadCloudFeeds()
        }) {
            NBNavigationStack {
                CustomFeedsListScreen()
                    .withNavigationDestinations()
            }
        }
    }
}
