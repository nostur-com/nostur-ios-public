/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

@propertyWrapper public struct ScrollOffset: DynamicProperty {
    @Environment(\.scrollPublisherID) private var scrollPublisherID
    @StateObject private var stateObject = ScrollOffsetStateObject()
    @State private var baseState = BaseScrollOffsetState.build()
    private var edge: Edge
    private var range: ClosedRange<CGFloat>
    private var scrollOffsetID: ScrollOffsetID
    
    @available(iOS 17, macOS 14, tvOS 17, visionOS 1, *)
    private var state: ScrollOffsetState {
        baseState as! ScrollOffsetState
    }
    
    public var wrappedValue: CGFloat {
        if #available(iOS 17, macOS 14, tvOS 17, visionOS 1, *) {
            state.value
        } else {
            stateObject.value
        }
    }
    
    public var projectedValue: ScrollOffsetProxy<CGFloat>.Value {
        .init(edge: edge, id: scrollOffsetID.id ?? scrollPublisherID)
    }
    
    public func update() {
        if #available(iOS 17, macOS 14, tvOS 17, visionOS 1, *) {
            state.update(edge: edge, id: scrollOffsetID.id ?? scrollPublisherID, range: range)
        } else {
            stateObject.update(edge: edge, id: scrollOffsetID.id ?? scrollPublisherID, range: range)
        }
    }
}


public extension ScrollOffset {
    init(_ edge: Edge, in range: ClosedRange<CGFloat> = -CGFloat.infinity...CGFloat.infinity, id: ScrollOffsetID = .automatic) {
        self.edge = edge
        self.range = range
        self.scrollOffsetID = id
    }
    
    init(_ edge: Edge, in range: PartialRangeFrom<CGFloat>, id: ScrollOffsetID = .automatic) {
        self.edge = edge
        self.range = range.lowerBound...CGFloat.infinity
        self.scrollOffsetID = id
    }
    
    init(_ edge: Edge, in range: PartialRangeThrough<CGFloat>, id: ScrollOffsetID = .automatic) {
        self.edge = edge
        self.range = -CGFloat.infinity...range.upperBound
        self.scrollOffsetID = id
    }
    
    init(_ edge: Edge, in range: ClosedRange<CGFloat> = -CGFloat.infinity...CGFloat.infinity, id: some Hashable) {
        self.edge = edge
        self.range = range
        self.scrollOffsetID = .custom(id)
    }
    
    init(_ edge: Edge, in range: PartialRangeFrom<CGFloat>, id: some Hashable) {
        self.edge = edge
        self.range = range.lowerBound...CGFloat.infinity
        self.scrollOffsetID = .custom(id)
    }
    
    init(_ edge: Edge, in range: PartialRangeThrough<CGFloat>, id: some Hashable) {
        self.edge = edge
        self.range = -CGFloat.infinity...range.upperBound
        self.scrollOffsetID = .custom(id)
    }
}


public extension ScrollOffset {
    static func proxy(_ edge: Edge, id: some Hashable) -> ScrollOffsetProxy<CGFloat>.Value {
        .init(edge: edge, id: id)
    }
    
    static func proxy(_ corner: Corner, id: some Hashable) -> ScrollOffsetProxy<CGPoint>.Value {
        .init(corner: corner, id: id)
    }
}
