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
        navigationTitle = "＿"
    }
    
    static func == (lhs: TabModel, rhs: TabModel) -> Bool {
        return lhs.id == rhs.id
    }
}

final class DetailTabsModel: ObservableObject {
    
    static public let shared = DetailTabsModel()
    
    @Published var tabs:[TabModel] = []
    @Published var selected:TabModel? = nil
}
