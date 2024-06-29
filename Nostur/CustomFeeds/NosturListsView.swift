//
//  NosturListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//

import SwiftUI
import NavigationBackport

struct NosturListsView: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath:\CloudFeed.createdAt, ascending: false)])
    var lists: FetchedResults<CloudFeed>
    
    @State var confirmDeleteShown = false
    @State var listToDelete: CloudFeed? = nil
    @State var newListSheet = false
    @State private var didRemoveDuplicates = false
    
    @AppStorage("enable_hot_feed") private var enableHotFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true
        
    var body: some View {
        VStack {
            
            List {
                if !lists.isEmpty {
                    Section {
                        ForEach(lists) { list in
                            NBNavigationLink(value: list) {
                                ListRow(list: list)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    listToDelete = list
                                    confirmDeleteShown = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                            }
                            .listRowBackground(themes.theme.background)
                        }
                    } header: {
                        Text("Custom Feeds")
                    }
                }
                
                Section {
                    Toggle(isOn: $enableHotFeed, label: {
                        Text("Hot")
                        Text("Posts most liked or reposted by people you follow")
                    })
                    Toggle(isOn: $enableGalleryFeed, label: {
                        Text("Gallery")
                        Text("Media from posts most liked or reposted by people you follow")
                    })
                    Toggle(isOn: $enableArticleFeed, label: {
                        Text("Articles")
                        Text("Long-form articles from people you follow")
                    })
                    Toggle(isOn: $enableExploreFeed, label: {
                        Text("Explore")
                        Text("Posts from people followed by the [Explore Feed](nostur:p:afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320) account")
                    })
                } header: {
                    Text("Default feeds")
                } footer: {
                    Text("Hot, Gallery, and Articles feed will not be visible if you don't follow more than 10 people.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(String(localized:"Create new feed", comment: "Button to create a new feed")) {
                    newListSheet = true
                }
            }
        }
        .navigationTitle(String(localized:"Feeds", comment: "Navigation title for Feeds screen"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete feed \(listToDelete?.name ?? "")", isPresented: $confirmDeleteShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let listToDelete = listToDelete else { return }
                viewContext.delete(listToDelete)
                DataProvider.shared().save()
                self.listToDelete = nil
            }
        }
        .sheet(isPresented: $newListSheet) {
            NBNavigationStack {
                NewListSheet()
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .nosturNavBgCompat(themes: themes)
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
            pe.loadNosturLists()
        }) {
            NBNavigationStack {
                NosturListsView()
                    .withNavigationDestinations()
            }
        }
    }
}
