//
//  EventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2024.
//

import SwiftUI
import CoreData
import Combine

class EventViewModel: ObservableObject {
    let id: String
    let pubkey: String
    
    @Published var name: String?
    @Published var pfpUrl: String?
    @Published var isBookmarked: Bool
    
    init(id: String, pubkey: String, name: String, pfpUrl: String? = nil, isBookmarked: Bool = false) {
        self.id = id
        self.pubkey = pubkey
        self.name = name
        self.pfpUrl = pfpUrl
        self.isBookmarked = isBookmarked
    }
    
    func isRelevantUpdate(_ update: ProfileInfo) -> Bool {
        return update.pubkey == self.pubkey
    }
    
    func applyUpdate(_ update: ProfileInfo) {
        self.name = update.name
        self.pfpUrl = update.pfpUrl
    }
    
    func isRelevantUpdate(_ update: BookmarkUpdate) -> Bool {
        return update.id == self.id
    }
    
    func applyUpdate(_ update: BookmarkUpdate) {
        self.isBookmarked = update.isBookmarked
    }
}






