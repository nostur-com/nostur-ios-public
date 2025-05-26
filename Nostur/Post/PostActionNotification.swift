//
//  PostActionNotification.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2023.
//

import SwiftUI

struct PostActionNotification {
    let type: ActionType
    let eventId: String
    
    var bookmarked: Bool = false
    var hasPrivateNote: Bool = false
    
    enum ActionType {
        case bookmark(Color) // "orange", "red", "blue", "purple", "green"
        
        case reacted(UUID?, String) // cancellation uuid, reaction.content (like "+" or "😂")
        case unreacted(String) // reaction.content (like "+" or "😂")
        
        case reposted
        
        case replied
        case unreplied // (after Undo send)
        
        case zapped
        case unzapped
        
        case privateNote
    }
}
