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

enum ViewPath: Hashable {
    case Blocklist
    case Following(account:Account)
}

extension View {
    func withNavigationDestinations() -> some View {
        return self
            .navigationDestination(for: NotePath.self) { path in
                NoteById(id: path.id)
            }
            .navigationDestination(for: Event.self) { event in
                ReplyNoteView(event: event)
//                NoteDetail(event: event)
            }
            .navigationDestination(for: ContactPath.self) { path in
                ProfileByPubkey(pubkey: path.key)
            }
            .navigationDestination(for: Contact.self) { contact in
                Profile(contact: contact)
            }
            .navigationDestination(for: ViewPath.self) { path in
                switch (path) {
                    case .Blocklist:
                        BlockListView()
                    case .Following(let account):
                        AccountFollowingList(account: account)
                }
            }
    }
}

class NavigationModel: ObservableObject {
    
    static var shared = NavigationModel()
    
    @Published var showSidebar: Bool = false
    @Published var selectedTab = "Timeline"
    @Published var timelinePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var accountsPath = NavigationPath()
    @Published var bookmarksPath = NavigationPath()
    @Published var notificationsPath = NavigationPath()
    @Published var messagesPath = NavigationPath()
    @Published var configurationPath = NavigationPath()
    
    func navigateTo(_ path:any Hashable) -> Void {
        switch (selectedTab) {
            case "Timeline":
                self.timelinePath.append(path)
            case "Accounts":
                self.accountsPath.append(path)
            case "Bookmarks":
                self.bookmarksPath.append(path)
            case "Configuration":
                self.configurationPath.append(path)
            case "Messages":
                self.messagesPath.append(path)
            case "Notifications":
                self.notificationsPath.append(path)
            case "Search":
                self.searchPath.append(path)
            default:
                self.timelinePath.append(path)
        }
    }
}
