//
//  NXColumnViewModelInner.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2025.
//

import SwiftUI
import Combine

private struct NXColumnUnreadSnapshot: Equatable {
    var ids: [String: Int] = [:]
    var count: Int = 0
}

/// Isolated from `NXColumnViewModelInner` so unread bookkeeping does not
/// invalidate the entire feed. A mutation publishes one coherent snapshot.
final class NXColumnUnreadState: ObservableObject {
    @Published private var snapshot = NXColumnUnreadSnapshot()

    var unreadIds: [String: Int] {
        snapshot.ids
    }

    var unreadCount: Int {
        snapshot.count
    }

    fileprivate func replaceUnreadIds(_ unreadIds: [String: Int]) {
        guard unreadIds != snapshot.ids else { return }
        snapshot = NXColumnUnreadSnapshot(
            ids: unreadIds,
            count: unreadIds.values.reduce(0, +)
        )
    }
}

/// Mutable feed coordination state. UI updates are exposed through narrowly
/// scoped publishers instead of making the entire object observable.
class NXColumnViewModelInner {
    
    let unreadState = NXColumnUnreadState()

    // Compatibility accessors for callers that only need a snapshot or perform
    // a single mutation. Use updateUnreadIds(_:) to batch multiple changes.
    public var unreadIds: [String: Int] {
        get { unreadState.unreadIds }
        set {
            let previousUnreadCount = unreadState.unreadCount
            unreadState.replaceUnreadIds(newValue)
            let newUnreadCount = unreadState.unreadCount

            if #available(iOS 16.0, *),
               previousUnreadCount > 0,
               newUnreadCount == 0 {
                AppReviewManager.shared.didJustReachEndOfFeed = true
            }
            
#if DEBUG
            finishFirstUnreadMeasurementIfNeeded(previousUnreadCount: previousUnreadCount, newUnreadCount: newUnreadCount)
#endif
        }
    }
    
    public var unreadCount: Int {
        unreadState.unreadCount
    }

    public func updateUnreadIds(_ update: (inout [String: Int]) -> Void) {
        var unreadIds = unreadState.unreadIds
        update(&unreadIds)
        self.unreadIds = unreadIds
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
    
    /// Retains the current command so a scroll restoration request is not lost
    /// if it is sent just before NXPostsFeed subscribes.
    public let scrollToIndexSubject = CurrentValueSubject<Int?, Never>(nil)

    public func requestScroll(to index: Int) {
        scrollToIndexSubject.send(index)
    }

    public func clearScrollRequest() {
        scrollToIndexSubject.send(nil)
    }

    public var isAtTop: Bool = true
    
    public var updateIsAtTopSubject = PassthroughSubject<Void, Never>()
    
    // New properties for radical anti-flicker approach
    public var isPerformingScroll: Bool = false // if set, won't update unread ids by onAppear (new posts added on top, not read yet)
    public var isPreparingForScrollRestore = false
    public var pendingScrollToIndex: Int?
    public var pendingScrollToPostID: String?
    public var scrollRestoreStartedAt: Date?
    public static let scrollRestoreGraceInterval: TimeInterval = 0.5

    public var isPreparedScrollRestoreExpired: Bool {
        guard let scrollRestoreStartedAt else { return false }
        return Date().timeIntervalSince(scrollRestoreStartedAt) > Self.scrollRestoreGraceInterval
    }

    public func beginPreparedScrollRestore(postID: String, index: Int) {
        isPreparingForScrollRestore = true
        pendingScrollToIndex = index
        pendingScrollToPostID = postID
        scrollRestoreStartedAt = Date()
    }

    public func abortPreparedScrollRestore() {
        isPreparingForScrollRestore = false
        pendingScrollToIndex = nil
        pendingScrollToPostID = nil
        scrollRestoreStartedAt = nil
        clearScrollRequest()
    }
    /// Last post the user was parked on after restore or while reading mid-feed.
    /// Used so a later top-insert cannot be mistaken for "user is at the top".
    public var readingPostID: String?
    /// After restore, rows just above the parked post can sit a few points into
    /// the viewport and would be marked read. Keep them unread until the user
    /// actually drags the feed.
    public var holdUnreadAboveReadingPost = false

    /// Installed by the visible feed so passive list mutations can preserve the exact post and
    /// viewport offset the user is reading, even when rows are inserted above it.
    public var performAnchoredFeedUpdate: (([String], @escaping () -> Void) -> Void)?
    /// Cancels a leftover prepend settle so a bottom append cannot be pinned.
    public var cancelPendingFeedSettle: (() -> Void)?
    /// Small content-offset nudge after a bottom append (estimated row heights).
    public var preserveViewportAfterAppend: (() -> Void)?
    
    
    // Triggered by user, different from triggered by new posts coming in (.isPerformingScroll)
    // Rows crossed by the animation must not update unread state. The selected indexed target is
    // marked explicitly after scrolling settles because an already-instantiated row may not appear again.
    public var isPerformingScrollToFirstUnread: Bool = false
}
