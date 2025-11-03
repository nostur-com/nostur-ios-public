//
//  NotificationsColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/10/2025.
//


import SwiftUI
import NavigationBackport

struct NotificationsColumn: View {
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    public let pubkey: String
    @Binding var navPath: NBNavigationPath
    @StateObject private var nvm = NotificationsViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    TabButton(action: {
                        withAnimation {
                            nvm.tab = "Mentions"
                            nvm.markMentionsAsRead()
                        }
                    }, systemIcon: "text.bubble", selected: nvm.tab == "Mentions", unread: nvm.unreadMentions)
                    
                    TabButton(action: {
                        withAnimation {
                            nvm.tab = "New Posts"
                            nvm.markNewPostsAsRead()
                        }
                    }, systemIcon: "bell", selected: nvm.tab == "New Posts", unread: nvm.unreadNewPosts)
                    
                    TabButton(action: {
                        withAnimation {
                            nvm.tab = "Reactions"
                            nvm.markReactionsAsRead()
                        }
                    }, systemIcon: "heart", selected: nvm.tab == "Reactions", unread: nvm.unreadReactions_, muted: nvm.muteReactions)
                    
                    TabButton(action: {
                        withAnimation {
                            nvm.tab = "Reposts"
                            nvm.markRepostsAsRead()
                        }
                    }, systemIcon: "arrow.2.squarepath", selected: nvm.tab == "Reposts", unread: nvm.unreadReposts_, muted: nvm.muteReposts)
                    
                    TabButton(action: {
                        withAnimation {
                            nvm.tab = "Zaps"
                            nvm.markZapsAsRead()
                        }
                    }, systemIcon: "bolt", selected: nvm.tab == "Zaps", unread: nvm.muteZaps ? nvm.unreadFailedZaps_ : (nvm.unreadZaps_ + nvm.unreadFailedZaps_), muted: nvm.muteZaps)
                    
                    TabButton(action: {
                        withAnimation {
                            nvm.tab = "Followers"
                            nvm.markNewFollowersAsRead()
                        }
                    }, systemIcon: "person.3", selected: nvm.tab == "Followers", unread: nvm.unreadNewFollowers_, muted: nvm.muteFollows)
                }
                .frame(minWidth: availableWidth)
            }
            .frame(width: availableWidth)
            
            AvailableWidthContainer {
                switch (nvm.tab) {
                    case "Mentions", "Posts": // (old name was "Posts")
                        NotificationsMentions(pubkey: pubkey, navPath: $navPath)
                    case "New Posts":
                        NotificationsNewPosts(pubkey: pubkey, navPath: $navPath)
                    case "Reactions":
                        NotificationsReactions(pubkey: pubkey, navPath: $navPath)
                    case "Reposts":
                        NotificationsReposts(pubkey: pubkey, navPath: $navPath)
                    case "Zaps":
                        NotificationsZaps(pubkey: pubkey, navPath: $navPath)
                    case "Followers":
                        NotificationsFollowers(pubkey: pubkey, navPath: $navPath)
                    default:
                        EmptyView()
                }
            }
            .padding(.top, GUTTER)
            .background(theme.listBackground)
        }
        
        .onAppear {
            guard !nvm.didLoad else { return }
            nvm.load(pubkey)
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var navPath = NBNavigationPath()
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
        pe.loadZaps()
    }) {
        NBNavigationStack(path: $navPath) {
            NotificationsColumn(
                pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                navPath: $navPath
            )
        }
    }
}
