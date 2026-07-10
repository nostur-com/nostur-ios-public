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
    
    // Full IDs (not shortIds)
    @Published public var unreadIds: [String: Int] = [:] {
        didSet {
            let previousUnreadCount = oldValue.reduce(0, { $0 + $1.value })
            let newUnreadCount = unreadCount
            if #available(iOS 16.0, *) {
                if previousUnreadCount > 0 && newUnreadCount == 0 {
                    AppReviewManager.shared.didJustReachEndOfFeed = true
                }
            }
            
#if DEBUG
            finishFirstUnreadMeasurementIfNeeded(previousUnreadCount: previousUnreadCount, newUnreadCount: newUnreadCount)
#endif
        }
    }
    
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
#if DEBUG
    private var firstUnreadMeasurementStart: Date?
    private var firstUnreadMeasurementFeedName: String?
    
    public func startFirstUnreadMeasurement(feedName: String, reason: String) {
        firstUnreadMeasurementStart = Date()
        firstUnreadMeasurementFeedName = feedName
        L.og.debug("⏱️⏱️ \(feedName) visible, starting first unread measurement. reason: \(reason)")
    }
    
    private func finishFirstUnreadMeasurementIfNeeded(previousUnreadCount: Int, newUnreadCount: Int) {
        guard previousUnreadCount == 0, newUnreadCount > 0 else { return }
        guard let firstUnreadMeasurementStart else { return }
        
        let elapsed = Date().timeIntervalSince(firstUnreadMeasurementStart)
        let elapsedString = String(format: "%.3f", locale: Locale(identifier: "nl_NL"), elapsed)
        L.og.debug("⏱️⏱️ First new unread item on \(self.firstUnreadMeasurementFeedName ?? "feed") after \(elapsedString) sec")
        self.firstUnreadMeasurementStart = nil
        self.firstUnreadMeasurementFeedName = nil
    }
#endif
    
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
