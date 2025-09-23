//
//  NoiseFilter.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/07/2023.
//

import Foundation


class NoiseFilter {

    let target:Int = 50 // We want to reduce 600+ posts to 50
    
    let unreadPosts:[NRPost]
    
    init(unreadPosts: [NRPost]) {
        self.unreadPosts = unreadPosts
    }
    
    // Things we could scan for:
    // 1) GM's, PV's, Hello, Hi --- Somehow detect greeting
    // 2) 80% of post is emojis
    // 3) Interactions with person X --> replyTo.pubkey
    // 4) X replies by person Y
}
