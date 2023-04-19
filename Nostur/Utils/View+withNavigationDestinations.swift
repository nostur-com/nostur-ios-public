//
//  View+withNavigationDestinations.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

import Foundation
import SwiftUI

struct NotePath: Hashable {
    var id:String
}

struct ContactPath: Hashable {
    var key:String
}

struct HashtagPath: Hashable {
    var hashTag:String
}

enum ViewPath: Hashable {
    case Post(vPost:VPost)
    case Blocklist
    case Bookmarks(account:Account)
    case NoteReactions(event:Event)
    case NoteZaps(event:Event)
    case Settings
    case Lists
    case Relays
    case Badges
}

extension View {
    func withNavigationDestinations() -> some View {
        return self
            .navigationDestination(for: VPost.self) { vPost in
                PostDetailView(vPost: vPost)
            }
            .navigationDestination(for: NotePath.self) { path in
                NoteById(id: path.id)
            }
            .navigationDestination(for: ContactPath.self) { path in
                ProfileByPubkey(pubkey: path.key)
            }
            .navigationDestination(for: HashtagPath.self) { path in
                Search(hashtag: path.hashTag)
            }
            .navigationDestination(for: Contact.self) { contact in
                ProfileView(contact: contact)
            }
            .navigationDestination(for: Badge.self) { badge in
                BadgeDetailView(badge: badge.badge)
            }
            .navigationDestination(for: NosturList.self) { list in
                EditNosturList(list: list)
            }
            .navigationDestination(for: ViewPath.self) { path in
                switch (path) {
                    case .Post(let post):
                        PostDetailView(vPost: post)
                    case .Blocklist:
                        BlockListView()
                    case .Bookmarks(let account):
                        BookmarksView(account: account)
                    case .NoteReactions(let event):
                        NoteReactions(id: event.id)
                    case .NoteZaps(let event):
                        NoteZaps(event: event)
                    case .Settings:
                        Settings()
                    case .Lists:
                        NosturListsView()
                    case .Relays:
                        RelaysView()    
                    case .Badges:
                        BadgesView()
                }
            }
    }
}

struct NavigationDestination {
    let destination:any Hashable
}

func navigateTo(_ path:any Hashable) {
    sendNotification(.navigateTo, NavigationDestination(destination: path))
}

func navigateToOnMain(_ path:any Hashable) {
    sendNotification(.navigateToOnMain, NavigationDestination(destination: path))
}
