/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import Combine

internal final class ScrollSubscription {
    let contentOffsetCancellable: AnyCancellable
    let contentSizeCancellable: AnyCancellable
    var offset: ScrollOffsetValue
    weak var scrollView: PlatformScrollView?
    
    init(contentOffsetCancellable: AnyCancellable, contentSizeCancellable: AnyCancellable, scrollView: PlatformScrollView) {
        self.contentOffsetCancellable = contentOffsetCancellable
        self.contentSizeCancellable = contentSizeCancellable
        self.offset = ScrollOffsetValue(top: .zero, leading: .zero, bottom: .zero, trailing: .zero)
        self.scrollView = scrollView
    }
}
