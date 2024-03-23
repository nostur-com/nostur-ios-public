//
//  BookmarksAndPrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import NavigationBackport

struct BookmarksAndPrivateNotes: View {
    @EnvironmentObject private var fa: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    @State private var navPath = NBNavigationPath()

    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Bookmarks" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Bookmarks"
    

    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var bookmarksCount: String?
    @State private var privateNotesCount: String?
    
    @State private var bookmarkFilters: Set<Color> = [.red, .blue, .purple, .green, .orange]
    @State private var showBookmarkFilterOptions = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                HStack {
                    TabButton(
                        action: { selectedSubTab = "Bookmarks" },
                        title: String(localized: "Bookmarks", comment: "Tab to switch to bookmarks"),
                        secondaryText: bookmarksCount,
                        selected: selectedSubTab == "Bookmarks",
                        tools: {
                            Image(systemName: bookmarkFilters.count < 5 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .padding(.leading, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showBookmarkFilterOptions = true
                                }
                        }
                    )
                    
                    TabButton(action: {
                        selectedSubTab = "Private Notes"
                    }, title: String(localized: "Private Notes", comment: "Tab to switch to private notes"), secondaryText: privateNotesCount, selected: selectedSubTab == "Private Notes")
                }
                switch selectedSubTab {
                    case "Bookmarks":
                    BookmarksView(navPath: $navPath, bookmarkFilters: bookmarkFilters)
                    case "Private Notes":
                        PrivateNotesView(navPath: $navPath)
                    default:
                        Text("🥪")
                }
            }
            .background(themes.theme.listBackground)
            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            
            .onChange(of: bookmarkFilters) { newFilters in
                
                let bookmarkFiltersStringArray = newFilters.map {
                    return switch $0 {
                    case .orange:
                        "orange"
                    case .red:
                        "red"
                    case .blue:
                        "blue"
                    case .purple:
                        "purple"
                    case .green:
                        "green"
                    default:
                        "orange"
                    }
                }
                
                UserDefaults.standard.set(bookmarkFiltersStringArray, forKey: "bookmark_filters")
            }
            
            .onAppear {
                bookmarkFilters = Set<Color>((UserDefaults.standard.array(forKey: "bookmark_filters") as? [String] ?? ["red", "blue", "purple", "green", "orange"])
                    .map {
                        return switch $0 {
                            case "red":
                                Color.red
                            case "blue":
                                Color.blue
                            case "purple":
                                Color.purple
                            case "green":
                                Color.green
                            case "orange":
                                Color.orange
                            default:
                                Color.orange
                            
                        }
                    })
            }
            
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard !IS_IPAD || horizontalSizeClass == .compact else { return }
                guard selectedTab == "Bookmarks" else { return }
                navPath.append(destination.destination)
            }
            .onReceive(receiveNotification(.clearNavigation)) { notification in
                navPath.removeLast(navPath.count)
            }
            .onPreferenceChange(BookmarksCountPreferenceKey.self, perform: { value in
                bookmarksCount = value == "0" ? nil : value
            })
            .onPreferenceChange(PrivateNotesCountPreferenceKey.self, perform: { value in
                privateNotesCount = value == "0" ? nil : value
            })
            .sheet(isPresented: $showBookmarkFilterOptions, onDismiss: {
                showBookmarkFilterOptions = false
            }, content: {
                NBNavigationStack {
                    BookmarkFilters(onlyShow: $bookmarkFilters)
                        .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
            })
        }
        .nbUseNavigationStack(.never)
    }
}

struct BookmarksAndPrivateNotes_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadBookmarks()
            pe.loadPrivateNotes()
        }) {
            BookmarksAndPrivateNotes()
        }
    }
}
