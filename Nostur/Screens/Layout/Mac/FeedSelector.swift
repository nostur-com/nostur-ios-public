//
//  FeedSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/08/2023.
//

import SwiftUI
import NavigationBackport

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var feeds: [CloudFeed] = []
    @Previewable @State var selected: CloudFeed? = nil
    
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadCloudFeeds()
    }) {
        NBNavigationStack {
            Color.red
                .frame(width: 300, height: 600)
                .withFeedSelectorToolbarMenu(feeds: feeds, selectedFeed: $selected)
                .onAppear {
                    feeds = PreviewFetcher.fetchLists()
                    print("feeds: \(feeds.count)")
                }
        }
    }
}


@available(iOS 16.0, *)
struct FeedSelectorToolbarMenu: ViewModifier {
    let feeds: [CloudFeed]
    @Binding var selectedFeed: CloudFeed?
    
    func body(content: Content) -> some View {
        content
            .navigationTitle(selectedFeed?.feedTitle() ?? "Select Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarTitleMenu {
                  ForEach(feeds) { feed in
                      Button(feed.feedTitle()) {
                          selectedFeed = feed
                      }
                  }
              }
          }
    }
}

extension CloudFeed {
    func feedTitle() -> String {
        switch self.feedType {
            case .following(_):
                return self.name_
            case .picture(_):
                let accountName = self.account?.anyName ?? "?"
                return "Photos (\(accountName))"
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

extension View {
    @available(iOS 16.0, *)
    func withFeedSelectorToolbarMenu(feeds: [CloudFeed], selectedFeed: Binding<CloudFeed?>) -> some View {
        modifier(FeedSelectorToolbarMenu(feeds: feeds, selectedFeed: selectedFeed))
    }
}
