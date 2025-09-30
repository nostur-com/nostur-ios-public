/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import Combine
import Foundation

internal final class ScrollSubscriptionStore {
    static let shared = ScrollSubscriptionStore()
    private init() {}
    
    let offsetChangedSubject = PassthroughSubject<AnyHashable, Never>()
    
    subscript(offset id: AnyHashable) -> ScrollOffsetValue? {
        subscriptions[id]?.offset
    }
    
    subscript(scrollView id: AnyHashable) -> PlatformScrollView? {
        guard let subscription = subscriptions[id]
        else { return nil }
        
        if let scrollView = subscription.scrollView {
            return scrollView
        } else {
            subscriptions.removeValue(forKey: id)
            return nil
        }
    }
    
    @MainActor
    func subscribe(id: AnyHashable, scrollView: PlatformScrollView) {
        guard self[scrollView: id] != scrollView
        else { return }
        
        let contentOffsetCancellable = scrollView.subscribeToContentOffset {
            self.updateOffset(for: id)
        }
        
        let contentSizeCancellable = scrollView.subscribeToContentSize {
            self.updateOffset(for: id)
        }
        
        subscriptions[id] = ScrollSubscription(
            contentOffsetCancellable: contentOffsetCancellable,
            contentSizeCancellable: contentSizeCancellable,
            scrollView: scrollView
        )
        
        updateOffset(for: id)
    }
    
    func unsubscribe(id: AnyHashable) {
        DispatchQueue.main.async {
            if let subscription = self.subscriptions[id], subscription.scrollView == nil {
                self.subscriptions.removeValue(forKey: id)
            }
        }
    }
    
    @MainActor
    func updateOffset(for id: AnyHashable) {
        guard let scrollView = self[scrollView: id] else { return }
        
        let top = -scrollView.adjustedContentInset.top - scrollView.scrollContentOffset.y
        let bottom = scrollView.scrollContentSize.height
        - (scrollView.bounds.height - scrollView.adjustedContentInset.bottom)
        - scrollView.scrollContentOffset.y
        
        let left = -scrollView.adjustedContentInset.left - scrollView.scrollContentOffset.x
        let right = scrollView.scrollContentSize.width
        - (scrollView.bounds.width - scrollView.adjustedContentInset.right)
        - scrollView.scrollContentOffset.x
        
        let leading = scrollView.isRightToLeft ? -right : left
        let trailing = scrollView.isRightToLeft ? -left : right
        
        let currentValue = self[offset: id]
        let displayScale = scrollView.displayScale
        
        let (resolvedTop, didTopChange) = resolve(top, oldValue: currentValue?.top, scale: displayScale)
        let (resolvedLeading, didLeadingChange) = resolve(leading, oldValue: currentValue?.leading, scale: displayScale)
        let (resolvedBottom, didBottomChange) = resolve(bottom, oldValue: currentValue?.bottom, scale: displayScale)
        let (resolvedTrailing, didTrailingChange) = resolve(trailing, oldValue: currentValue?.trailing, scale: displayScale)
        
        if didTopChange || didLeadingChange || didBottomChange || didTrailingChange {
            subscriptions[id]?.offset = ScrollOffsetValue(
                top: resolvedTop,
                leading: resolvedLeading,
                bottom: resolvedBottom,
                trailing: resolvedTrailing
            )
            offsetChangedSubject.send(id)
        }
    }
    
    @MainActor
    func updateSubscription(from oldID: AnyHashable, to newID: AnyHashable) {
        subscriptions[newID] = subscriptions[oldID]
        subscriptions.removeValue(forKey: oldID)
    }
    
    private var subscriptions = [AnyHashable : ScrollSubscription]()
    
    private func resolve(_ first: CGFloat, oldValue second: CGFloat?, scale displayScale: CGFloat) -> (CGFloat, Bool) {
        let firstRounded = Int(round(first * displayScale))
        let secondRounded: Int? = if let second { Int(round(second * displayScale)) } else { nil }
        
        let rounded = CGFloat(firstRounded) / displayScale
        let didChange = firstRounded != secondRounded
        return (rounded, didChange)
    }
}
