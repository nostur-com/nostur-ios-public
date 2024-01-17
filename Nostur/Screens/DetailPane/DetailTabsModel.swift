//
//  TabModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import SwiftUI

class TabModel: ObservableObject, Identifiable, Equatable {
    
    var id:UUID
    var notePath:NotePath?
    var contactPath:ContactPath?
    var nrContactPath:NRContactPath?
    var event:Event?
    var nrPost:NRPost?
    var nrContact:NRContact?
    var naddr1:Naddr1Path?
    var articlePath:ArticlePath?
    var profileTab:String?
    var isArticle:Bool {
        naddr1 != nil || articlePath != nil
    }
    @Published var navigationTitle = "" {
        didSet {
            L.og.info("💄💄 navigationTitle set to \(self.navigationTitle)")
        }
    }
    
    @Published var suspended = false
    
    init(notePath:NotePath? = nil, contactPath:ContactPath? = nil, nrContactPath:NRContactPath? = nil, event:Event? = nil, nrContact:NRContact? = nil, nrPost:NRPost? = nil, naddr1:Naddr1Path? = nil, articlePath:ArticlePath? = nil, profileTab:String? = nil) {
        self.id = UUID()
        self.notePath = notePath
        self.contactPath = contactPath
        self.nrContactPath = nrContactPath
        self.event = event
        self.nrContact = nrContact
        self.nrPost = nrPost
        self.naddr1 = naddr1
        self.articlePath = articlePath
        self.profileTab = profileTab
        self.configureNavigationTitle()
    }
    
    private func configureNavigationTitle() {
        if let title = self.notePath?.navigationTitle {
            navigationTitle = title
            return
        }
        if let title = self.contactPath?.navigationTitle {
            navigationTitle = title
            return
        }
        if let title = self.naddr1?.navigationTitle {
            navigationTitle = title
            return
        }
        if let title = self.articlePath?.navigationTitle {
            navigationTitle = title
            return
        }
        if let nrPost = self.nrPost {
            navigationTitle = nrPost.anyName
            return
        }
        if let event = self.event {
            if let anyName = event.contact?.anyName {
                navigationTitle = anyName
                return
            }
            else {
                navigationTitle = String(event.pubkey.suffix(11))
                return
            }
        }
        if let contact = self.nrContact {
            navigationTitle = contact.anyName
            return
        }
        if let nrContact = self.nrContactPath?.nrContact {
            navigationTitle = nrContact.anyName
            return
        }
        navigationTitle = "＿"
    }
    
    static func == (lhs: TabModel, rhs: TabModel) -> Bool {
        return lhs.id == rhs.id
    }
}

import NostrEssentials
typealias si = NostrEssentials.ShareableIdentifier

final class DetailTabsModel: ObservableObject {
    
    static public let shared = DetailTabsModel()
    
    @Published var tabs: [TabModel] = [] {
        didSet {
            self.saveTabs()
        }
    }
    @Published var selected: TabModel? = nil {
        didSet {
            self.saveTabs()
        }
    }
    
    @AppStorage("saved_tabs") private var savedTabs = "[]"
    
    public func saveTabs() {
        let saveableTabs:[SavedTab] = tabs.compactMap { tab in
            if let id = tab.notePath?.id, let identifier = try? si("nevent", id: id).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let pubkey = tab.contactPath?.key, let identifier = try? si("nprofile", pubkey: pubkey).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let pubkey = tab.nrContact?.pubkey, let identifier = try? si("nprofile", pubkey: pubkey).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let pubkey = tab.nrContactPath?.nrContact.pubkey, let identifier = try? si("nprofile", pubkey: pubkey).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let id = tab.event?.id, let identifier = try? si("nevent", id: id).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let id = tab.nrPost?.id, let identifier = try? si("nevent", id: id).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let id = tab.articlePath?.id, let identifier = try? si("nevent", id: id).identifier {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: identifier, selected: tab == self.selected)
            }
            else if let naddr1 = tab.naddr1?.naddr1 {
                return SavedTab(title: tab.navigationTitle, nostrIdentifier: naddr1, selected: tab == self.selected)
            }
            return nil
        }
        DispatchQueue.global().async { // its doing slow bech32 things, so not on main
            guard let savedTabsData = try? JSONEncoder().encode(saveableTabs) else { return }
            guard let savedTabsString = String(data: savedTabsData, encoding: .utf8) else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.savedTabs = savedTabsString
            }
        }
    }
    
    public func restoreTabs() {
        signpost(self, "Remember tabs", .begin, "Restoring tabs")
        guard let savedTabsData = savedTabs.data(using: .utf8),
              let restorableTabs = try? JSONDecoder().decode([SavedTab].self, from: savedTabsData)
        else { return }
        signpost(self, "Remember tabs", .event, "Decoded from storage")
        
        for tab in restorableTabs {
            guard let si = try? si(tab.nostrIdentifier) else { continue }
            switch si.prefix {
            case "nevent":
                guard let id = si.id else { continue }
                let tabModel = TabModel(notePath: NotePath(id: id, navigationTitle: tab.title))
                tabModel.suspended = true
                self.tabs.append(tabModel)
                if tab.selected {
                    tabModel.suspended = false
                    self.selected = tabModel
                }
            case "nprofile":
                guard let pubkey = si.pubkey else { continue }
                let tabModel = TabModel(contactPath: ContactPath(key: pubkey, navigationTitle: tab.title))
                tabModel.suspended = true
                self.tabs.append(tabModel)
                tabModel.suspended = true
                if tab.selected {
                    tabModel.suspended = false
                    self.selected = tabModel
                }
            case "naddr":
                let tabModel = TabModel(naddr1: Naddr1Path(naddr1: si.identifier, navigationTitle: tab.title))
                self.tabs.append(tabModel)
                tabModel.suspended = true
                if tab.selected {
                    tabModel.suspended = false
                    self.selected = tabModel
                }
            default:
                continue
            }
        }

        signpost(self, "Remember tabs", .event, "TabModels instantiated and appended to view model")
        
        if self.selected == nil && !self.tabs.isEmpty {
            self.selected = self.tabs.first
            self.selected?.suspended = false
        }
        
        signpost(self, "Remember tabs", .end, "Finished")
    }
}


struct SavedTab: Codable {
    let title:String
    let nostrIdentifier:String
    let selected:Bool
}
