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
    
    @Published public var unreadIds: [String: Int] = [:]
    
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
    @Published public var scrollToIndex: Int?
    
    @Published public var isAtTop: Bool = true
    
    // TODO: Put updateIsAtTopSubject here or on NXColumnViewModel? Doesn't matter?
    public var updateIsAtTopSubject = PassthroughSubject<Void, Never>()
    
    // New properties for radical anti-flicker approach
    public var isPerformingScroll: Bool = false
    public var isPreparingForScrollRestore = false
    public var pendingScrollToIndex: Int?
}
