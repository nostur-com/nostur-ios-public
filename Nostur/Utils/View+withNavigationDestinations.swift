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

struct Nevent1Path: Hashable {
    var nevent1:String
}

struct Nprofile1Path: Hashable {
    var nprofile1:String
}

enum ViewPath: Hashable {
    case Post(nrPost:NRPost)
    case Blocklist
    case Bookmarks(account:Account)
    case NoteReactions(id:String)
    case NoteZaps(id:String)
    case Settings
    case Lists
    case Relays
    case Badges
}

extension View {
    func withNavigationDestinations() -> some View {
        return self
            .navigationDestination(for: NRPost.self) { nrPost in
                PostDetailView(nrPost: nrPost)
            }
            .navigationDestination(for: NotePath.self) { path in
                NoteById(id: path.id)
            }
            .navigationDestination(for: ContactPath.self) { path in
                ProfileByPubkey(pubkey: path.key)
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
                        PostDetailView(nrPost: post)
                    case .Blocklist:
                        BlockListView()
                    case .Bookmarks(let account):
                        BookmarksView(account: account)
                    case .NoteReactions(let id):
                        NoteReactions(id: id)
                    case .NoteZaps(let id):
                        NoteZaps(id: id)
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
