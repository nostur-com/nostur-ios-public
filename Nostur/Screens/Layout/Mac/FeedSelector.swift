//
//  FeedSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/08/2023.
//

import SwiftUI
import NavigationBackport

extension CloudFeed {
    func feedTitle() -> String {
        switch self.feedType {
            case .following(_):
                return self.name_
            case .picture(_):
                return String(localized: "Photos")
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
    let feeds: [CloudFeed]
    @Binding var columnType: MacColumnType
    var title: String = "Select Feed"
    
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
                          
                          ToolbarItem(placement: .topBarTrailing) {
                              if case .notifications(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
                                  Button {
                                      
                                  } label: {
                                      PFP(pubkey: accountPubkey, account: account, size: 30)
                                  }
                                  .accessibilityLabel("Account menu")
                              }
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
                            
                            ToolbarItem(placement: .topBarTrailing) {
                                if case .notifications(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
                                    Button {
                                        
                                    } label: {
                                        PFP(pubkey: accountPubkey, account: account, size: 30)
                                    }
                                    .accessibilityLabel("Account menu")
                                }
                            }
                        }
                }
          }
    }
    
    @ViewBuilder
    private var menuItems: some View {
        Button("Hot") {
            columnType = .hot
        }
        
        Button("Funny") {
            columnType = .emoji
        }
        
        Button("Zapped") {
            columnType = .zapped
        }
        
        Button("Reads") {
            columnType = .articles
        }
        
        Button("Gallery") {
            columnType = .gallery
        }
        
        Button("Lists & Follow Packs") {
            columnType = .discoverLists
        }

        ForEach(feeds) { feed in
            Button(feed.feedTitle()) {
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
