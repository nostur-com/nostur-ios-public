/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

public extension ScrollOffsetProxy {
    struct Value {
        internal let edges: Edge.Set
        internal let id: AnyHashable?
        internal let resolveOffset: (Edge.Set, ScrollOffsetValue?) -> Offset
        internal let resolveScrollOffsetValue: (Edge.Set, Offset) -> ScrollOffsetValue
        
        public var offset: Offset {
            let offset: ScrollOffsetValue? = if let id {
                ScrollSubscriptionStore.shared[offset: id]
            } else {
                nil
            }
            return resolveOffset(edges, offset)
        }
        
        @MainActor
        public nonmutating func scrollTo(_ offset: Offset, withAnimation: Bool = false) {
            guard let id,
                  let oldOffset = ScrollSubscriptionStore.shared[offset: id],
                  let scrollView = ScrollSubscriptionStore.shared[scrollView: id]
            else { return }
            
            let newOffset = resolveScrollOffsetValue(edges, offset)
            var contentOffset = scrollView.scrollContentOffset
            
            if !newOffset.leading.isNaN {
                let change = newOffset.leading - oldOffset.leading
                contentOffset.x -= change * (scrollView.isRightToLeft ? -1 : 1)
            }
            if !newOffset.trailing.isNaN {
                let change = newOffset.trailing - oldOffset.trailing
                contentOffset.x -= change * (scrollView.isRightToLeft ? -1 : 1)
            }
            if !newOffset.top.isNaN {
                contentOffset.y -= newOffset.top - oldOffset.top
            }
            if !newOffset.bottom.isNaN {
                contentOffset.y -= newOffset.bottom - oldOffset.bottom
            }
            
            let top = -scrollView.adjustedContentInset.top
            let bottom = scrollView.scrollContentSize.height
            - (scrollView.bounds.height - scrollView.adjustedContentInset.bottom)
            
            let left = -scrollView.adjustedContentInset.left
            let right = scrollView.scrollContentSize.width
            - (scrollView.bounds.width - scrollView.adjustedContentInset.right)
            
            contentOffset.x = min(max(contentOffset.x, left), right)
            contentOffset.y = min(max(contentOffset.y, top), bottom)
            
            scrollView.setContentOffset(contentOffset, animated: withAnimation)
        }
    }
}
