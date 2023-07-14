//
//  Community.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/07/2023.
//
//

import Foundation

class Community: Identifiable, Equatable {
    
    let id:String // maybe use 'a'?
    var title:String
    var image:String?
    var moderators:[NRContact]
    var pubkey:String
    var admin:NRContact?
    
    init(event: Event) {
        self.pubkey = event.pubkey
        self.id = event.aTag
        self.title = event.communityName
        self.image = event.communityImage
        self.moderators = []
    }
    
    static func == (lhs: Community, rhs: Community) -> Bool {
        lhs.id == rhs.id
    }
}
