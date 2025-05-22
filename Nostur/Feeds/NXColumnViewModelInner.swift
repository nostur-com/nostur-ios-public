//
//  NXColumnViewModelInner.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2025.
//

import SwiftUI
import Combine

// These vars change a lot but trigger rerender on NXPostFeed when not needed
// So moved to separate NXColumnViewModelInner
class NXColumnViewModelInner: ObservableObject {
    
    @Published public var unreadIds: [String: Int] = [:] {
        didSet {
            if #available(iOS 16.0, *) {
                if oldValue.reduce(0, { $0 + $1.value }) > 0 && unreadCount == 0 {
                    AppReviewManager.shared.didJustReachEndOfFeed = true
                }
            }
        }
    }
    
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
    @Published public var scrollToIndex: Int?
    
    @Published public var isAtTop: Bool = true
    
    public var updateIsAtTopSubject = PassthroughSubject<Void, Never>()
    
    // New properties for radical anti-flicker approach
    public var isPerformingScroll: Bool = false // if set, won't update unread ids by onAppear (new posts added on top, not read yet)
    public var isPreparingForScrollRestore = false
    public var pendingScrollToIndex: Int?
    
    
    // Triggered by user, different from triggered by new posts coming in (.isPerformingScroll)
    // so here onAppear is triggered and should update unread ids
    public var isPerformingScrollToFirstUnread: Bool = false
}
