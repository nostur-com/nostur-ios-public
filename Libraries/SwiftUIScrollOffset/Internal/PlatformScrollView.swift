/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import Combine

#if canImport(UIKit)

import UIKit
internal typealias PlatformScrollView = UIScrollView

internal extension UIScrollView {
    var displayScale: CGFloat {
        traitCollection.displayScale
    }
    
    var isRightToLeft: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }
    
    var scrollContentOffset: CGPoint {
        contentOffset
    }
    
    var scrollContentSize: CGSize {
        contentSize
    }
    
    func subscribeToContentOffset(_ sink: @escaping () -> Void) -> AnyCancellable {
        self
            .publisher(for: \.contentOffset, options: [.initial, .new])
            .didChange()
            .sink(receiveValue: sink)
    }
    
    func subscribeToContentSize(_ sink: @escaping () -> Void) -> AnyCancellable {
        self
            .publisher(for: \.contentSize, options: [.initial, .new])
            .didChange()
            .sink(receiveValue: sink)
    }
}

#elseif canImport(AppKit)

import AppKit
internal typealias PlatformScrollView = NSScrollView

internal extension NSScrollView {
    var adjustedContentInset: NSEdgeInsets {
        contentInsets
    }
    
    var displayScale: CGFloat {
        window?.backingScaleFactor ?? 1
    }
    
    var isRightToLeft: Bool {
        userInterfaceLayoutDirection == .rightToLeft
    }
    
    var scrollContentOffset: CGPoint {
        documentVisibleRect.origin
    }
    
    var scrollContentSize: CGSize {
        documentView?.frame.size ?? .zero
    }
    
    func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        guard contentOffset != scrollContentOffset
        else { return }
        
        if animated {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.3
            contentView.animator().setBoundsOrigin(contentOffset)
            reflectScrolledClipView(contentView)
            NSAnimationContext.endGrouping()
            flashScrollers()
        } else {
            contentView.setBoundsOrigin(contentOffset)
        }
    }
    
    func subscribeToContentOffset(_ sink: @escaping () -> Void) -> AnyCancellable {
        contentView.postsBoundsChangedNotifications = true
        
        return NotificationCenter.default
            .publisher(for: NSView.boundsDidChangeNotification)
            .filter { [weak self] x in
                guard let self,
                      let view = x.object as? NSView
                else { return false }
                
                return view == self.contentView
            }
            .sink { _ in sink() }
    }
    
    func subscribeToContentSize(_ sink: @escaping () -> Void) -> AnyCancellable {
        contentView.postsFrameChangedNotifications = true
        
        return NotificationCenter.default
            .publisher(for: NSView.frameDidChangeNotification)
            .filter { [weak self] x in
                guard let self,
                      let view = x.object as? NSView
                else { return false }
                
                return view == self.contentView
            }
            .sink { _ in sink() }
    }
}

#endif
