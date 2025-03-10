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
    
    @Published public var unreadIds: [String: Int] = [:]
    
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
    @Published public var scrollToIndex: Int?
    public var isScrollingToIndex = false
    @Published public var isAtTop: Bool = true
}
