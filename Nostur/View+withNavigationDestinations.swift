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
    case Bookmarks(account:Account)
    case Account(account:Account)
    case NoteReactions(event:Event)
    case NoteZaps(event:Event)
    case Settings
    
    case Welcome
    case CreateNewAccount
    case UseExistingAccount
    case TryGuestAccount
    
    case Badges
}

extension View {
    func withNavigationDestinations() -> some View {
        return self
            .navigationDestination(for: NotePath.self) { path in
                NoteById(id: path.id)
            }
            .navigationDestination(for: Event.self) { event in
                NoteDetail(event: event)
            }
            .navigationDestination(for: ContactPath.self) { path in
                ProfileByPubkey(pubkey: path.key)
            }
            .navigationDestination(for: Contact.self) { contact in
                Profile(contact: contact)
            }
            .navigationDestination(for: Badge.self) { badge in
                BadgeDetailView(badge: badge.badge)
            }
//            .navigationDestination(for: Badge.self) { badge in
//                BadgeDetailView(badge: badge.badge)
//            }
            .navigationDestination(for: ViewPath.self) { path in
                switch (path) {
                    case .Blocklist:
                        BlockListView()
                    case .Bookmarks(let account):
                        BookmarksView(account: account)
                    case .Account(let account):
                        AccountEditView(account: account)
                    case .NoteReactions(let event):
                        NoteReactions(id: event.id)
                    case .NoteZaps(let event):
                        NoteZaps(id: event.id)
                    case .Settings:
                        Settings()
                    
                    case .Welcome:
                        WelcomeSheet()
                    case .CreateNewAccount:
                        NewAccountSheet()
                    case .UseExistingAccount:
                        AddExistingAccountSheet(offerTryOut: true)
                    case .TryGuestAccount:
                        TryGuestAccountSheet() // TODO:
                        
                    case .Badges:
                        BadgesView()
                }
            }
    }
}

class NavigationModel: ObservableObject {
    
    static var shared = NavigationModel()
    public var modelType = "NORMAL"
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @Published var tabPath = NavigationPath()
    @Published var mainPath = NavigationPath()
//    @Published var timelinePath = NavigationPath()
//    @Published var explorePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var accountsPath = NavigationPath()
    @Published var bookmarksPath = NavigationPath()
    @Published var notificationsPath = NavigationPath()
    @Published var messagesPath = NavigationPath()
    @Published var configurationPath = NavigationPath()
    @Published var detailPath = NavigationPath()
    @Published var onboardingPath = NavigationPath()
    
    init(modelType:String = "NORMAL") {
        self.modelType = modelType
    }
    
    let tm:DetailTabsModel = .shared
    
    func navigateTo(_ path:any Hashable) -> Void {
        if modelType == "TAB" {
            self.tabPath.append(path)
            return
        }
        if IS_IPAD {
            if type(of: path) == Event.self {
                let p = path as! Event
                let tab = DetailTabsModel.Tab(id: p.id, event: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: path) == NotePath.self {
                let p = path as! NotePath
                let tab = DetailTabsModel.Tab(id: p.id, notePath: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: path) == ContactPath.self {
                let c = path as! ContactPath
                let tab = DetailTabsModel.Tab(id: c.key, contactPath: c)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
        }
        switch (selectedTab) {
            case "Main":
                self.mainPath.append(path)
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
                self.mainPath.append(path)
        }
    }
    
    func clear() -> Void {
        switch (selectedTab) {
            case "Main":
                self.mainPath.removeLast(self.accountsPath.count)
                self.detailPath.removeLast(self.detailPath.count)
            case "Accounts":
                self.accountsPath.removeLast(self.accountsPath.count)
            case "Bookmarks":
                self.bookmarksPath.removeLast(self.bookmarksPath.count)
            case "Configuration":
                self.configurationPath.removeLast(self.configurationPath.count)
            case "Messages":
                self.messagesPath.removeLast(self.messagesPath.count)
            case "Notifications":
                self.notificationsPath.removeLast(self.notificationsPath.count)
            case "Search":
                self.searchPath.removeLast(self.searchPath.count)
            default:
                self.mainPath.removeLast(self.mainPath.count)
        }
    }
}
