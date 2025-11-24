//
//  FeedSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/08/2023.
//

import SwiftUI
import NavigationBackport

extension CloudFeed {
    func feedIconName() -> String {
        switch self.feedType {
            case .following(_):
                return "person.circle"
            case .picture(_):
                return "photo"
            case .yak(_):
                return "waveform.circle"
            case .vine(_):
                return "person.crop.square.badge.video"
            case .pubkeys(_):
                return "star"
            case .relays(_):
                return "star"
            case .followSet(_), .followPack(_):
                return "star"
            default:
                return "star"
        }
    }
    
    func feedTitle() -> String {
        switch self.feedType {
            case .following(_):
                return self.name_
            case .picture(_):
                return String(localized: "Photos")
            case .vine(_):
                return String(localized: "diVines")
            case .yak(_):
                return String(localized: "Yaks")
            case .pubkeys(_):
                return self.name_
            case .relays(_):
                return self.name_
            case .followSet(_), .followPack(_):
                return self.name_
            default:
                return self.name_
        }
    }
}

struct ColumnConfigToolbarMenu: ViewModifier {
    
    @AppStorage("enable_zapped_feed") private var enableZappedFeed: Bool = true
    @AppStorage("enable_hot_feed") private var enableHotFeed: Bool = true
    @AppStorage("enable_picture_feed") private var enablePictureFeed: Bool = true
    @AppStorage("enable_yak_feed") private var enableYakFeed: Bool = true
    @AppStorage("enable_vine_feed") private var enableVineFeed: Bool = true
    @AppStorage("enable_emoji_feed") private var enableEmojiFeed: Bool = true
    @AppStorage("enable_discover_feed") private var enableDiscoverFeed: Bool = true
    @AppStorage("enable_discover_lists_feed") private var enableDiscoverListsFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true
    
    let feeds: [CloudFeed]
    @Binding var columnType: MacColumnType
    var title: String = "Select Feed" // need title here instead of on views to build the title menu for pre iOS 16
    
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .modifier {
                if #available(iOS 16.0, *) {
                    $0.navigationTitle(title)
                      .toolbar {
                          ToolbarTitleMenu {
                              menuItems
                          }
                    }
                }
                else {
                    $0
                        .toolbar {
                            ToolbarItem(placement: .title) {
                                Menu {
                                    menuItems
                                } label: {
                                    HStack {
                                        Text(title)
                                        Image(systemName: "chevron.down.circle.fill")
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                }
          }
    }
    
    @ViewBuilder
    private var menuItems: some View {
        
        if enableHotFeed {
            Button("Hot", systemImage: "flame") {
                columnType = .hot
            }
        }

        if enableEmojiFeed {
            Button { columnType = .emoji } label: {
                Label {
                    Text("Funny")
                } icon: {
                    Image("LaughterIcon")
                        .renderingMode(.template)
                }
            }
        }
        
        if enableZappedFeed {
            Button("Zapped", systemImage: "bolt") {
                columnType = .zapped
            }
        }
        
        if enableArticleFeed {
            Button("Reads", systemImage: "newspaper") {
                columnType = .articles
            }
        }
        
        if enableGalleryFeed {
            Button("Gallery", systemImage: "photo.on.rectangle.angled") {
                columnType = .gallery
            }
        }
        
        Button("Follow Packs & Lists", systemImage: "person.2.crop.square.stack") {
            columnType = .discoverLists
        }
        
        Button("Notifications", systemImage: "bell") {
            columnType = .notifications(nil)
        }
        
        Button("New Posts", systemImage: "bell") {
            columnType = .newPosts
        }
        
        Button("Bookmarks", systemImage: "bookmark") {
            columnType = .bookmarks(Set(BOOKMARK_COLORS))
        }
        
        if enableExploreFeed {
            Button("Explore", systemImage: "binoculars") {
                columnType = .explore
            }
        }
        
        Divider()
        
        if enableYakFeed {
            Button("Yaks", systemImage: "waveform.circle") {
                columnType = .yaks(Nostur.account()?.publicKey)
            }
        }
        
        if enableVineFeed {
            Button("diVines", systemImage: "person.crop.square.badge.video") {
                columnType = .vines(Nostur.account()?.publicKey)
            }
        }
        
        if enablePictureFeed {
            Button("Photos", systemImage: "photo") {
                columnType = .photos(Nostur.account()?.publicKey)
            }
        }

        ForEach(feeds) { feed in
            Button(feed.feedTitle(), systemImage: feed.feedIconName()) {
                guard let feedId = feed.id?.uuidString else { return }
                columnType = .cloudFeed(feedId)
            }
        }
    }
}

extension View {
    func withColumnConfigToolbarMenu(feeds: [CloudFeed], columnType: Binding<MacColumnType>, title: String = "Select Feed") -> some View {
        modifier(ColumnConfigToolbarMenu(feeds: feeds, columnType: columnType, title: title))
    }
}


@available(iOS 17.0, *)
#Preview {
    @Previewable @State var columnType = MacColumnType.hot
    
    @Previewable @State var feeds: [CloudFeed] = []
    @Previewable @State var selected: CloudFeed? = nil
    
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadCloudFeeds()
    }) {
        NBNavigationStack {
            Color.red
                .frame(width: 300, height: 600)
                .withColumnConfigToolbarMenu(feeds: feeds, columnType: $columnType)
                .onAppear {
                    feeds = PreviewFetcher.fetchLists()
                    print("feeds: \(feeds.count)")
                }
        }
    }
}
