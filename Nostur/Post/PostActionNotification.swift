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
        case liked(UUID)
        case unliked
        case reposted
        case replied
        case privateNote
    }
}
