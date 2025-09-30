/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

extension View {
    @MainActor
    public func scrollOffsetID(_ id: ScrollOffsetID) -> some View {
        modifier(ScrollOffsetSubscriber(scrollOffsetID: id))
    }
    
    @_disfavoredOverload
    @MainActor
    public func scrollOffsetID(_ id: some Hashable) -> some View {
        modifier(ScrollOffsetSubscriber(scrollOffsetID: .custom(id)))
    }
}


extension View {
    public func ignoresScrollOffset(_ isIgnored: Bool = true) -> some View {
        transformEnvironment(\.scrollPublisherID) { id in
            if isIgnored {
                id = nil
            }
        }
    }
}
