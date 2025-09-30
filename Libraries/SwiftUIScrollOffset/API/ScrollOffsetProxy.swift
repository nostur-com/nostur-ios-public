/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

@propertyWrapper public struct ScrollOffsetProxy<Offset>: DynamicProperty {
    @Environment(\.scrollPublisherID) private var scrollPublisherID
    private var resolveProxy: (AnyHashable?) -> Value
    
    public var wrappedValue: Value {
        resolveProxy(scrollPublisherID)
    }
}


public extension ScrollOffsetProxy where Offset == CGFloat {
    init(_ edge: Edge, id: ScrollOffsetID = .automatic) {
        self.resolveProxy = { viewID in .init(edge: edge, id: id.id ?? viewID) }
    }
    
    init(_ edge: Edge, id: some Hashable) {
        self.resolveProxy = { _ in .init(edge: edge, id: id) }
    }
}


public extension ScrollOffsetProxy where Offset == CGPoint {
    init(_ corner: Corner, id: ScrollOffsetID = .automatic) {
        self.resolveProxy = { viewID in .init(corner: corner, id: id.id ?? viewID) }
    }
    
    init(_ corner: Corner, id: some Hashable) {
        self.resolveProxy = { _ in .init(corner: corner, id: id) }
    }
}
