//
//  NXColumnViewModelInner.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2025.
//

import SwiftUI

// These vars change a lot but trigger rerender on NXPostFeed when not needed
// So moved to separate NXColumnViewModelInner
class NXColumnViewModelInner: ObservableObject {
    
    @Published public var unreadIds: [String: Int] = [:] { // Dict of [post id: posts count (post + parent posts)]
        didSet {
            if unreadCount == 0 {
                if !isAtTop {
                    isAtTop = true
                }
            }
        }
    }
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
    @Published public var scrollToIndex: Int?
    @Published public var isAtTop: Bool = true
}