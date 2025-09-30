/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

internal extension CGFloat {
    init(edges: Edge.Set, value: ScrollOffsetValue?) {
        self = if let value {
            if edges.contains(.top) {
                value.top
            } else if edges.contains(.leading) {
                value.leading
            } else if edges.contains(.bottom) {
                value.bottom
            } else if edges.contains(.trailing) {
                value.trailing
            } else {
                .zero
            }
        } else {
            .zero
        }
    }
}


internal extension CGPoint {
    init(edges: Edge.Set, value: ScrollOffsetValue?) {
        self = .zero
        
        if let value {
            if edges.contains(.top) {
                self.y = value.top
            } else if edges.contains(.leading) {
                self.x = value.leading
            } else if edges.contains(.bottom) {
                self.y = value.bottom
            } else if edges.contains(.trailing) {
                self.x = value.trailing
            }
        }
    }
}


internal extension Corner {
    var edges: Edge.Set {
        switch self {
        case .topLeading: [.top, .leading]
        case .bottomLeading: [.bottom, .leading]
        case .bottomTrailing: [.bottom, .trailing]
        case .topTrailing: [.top, .trailing]
        }
    }
}


internal extension ScrollOffsetID {
    var id: AnyHashable? {
        switch self {
        case .automatic: nil
        case .custom(let id): id
        }
    }
}


internal extension ScrollOffsetProxy.Value {
    init(edge: Edge, id: AnyHashable?)
    where Offset == CGFloat
    {
        self.edges = Edge.Set(edge)
        self.id = id
        self.resolveOffset = Offset.init
        self.resolveScrollOffsetValue = ScrollOffsetValue.init
    }
    
    init(corner: Corner, id: AnyHashable?)
    where Offset == CGPoint
    {
        self.edges = corner.edges
        self.id = id
        self.resolveOffset = Offset.init
        self.resolveScrollOffsetValue = ScrollOffsetValue.init
    }
}


internal extension ScrollOffsetValue {
    init(edges: Edge.Set, value: CGFloat) {
        self.init(
            top: edges.contains(.top) ? value : .nan,
            leading: edges.contains(.leading) ? value : .nan,
            bottom: edges.contains(.bottom) ? value : .nan,
            trailing: edges.contains(.trailing) ? value : .nan
        )
    }
    
    init(edges: Edge.Set, value: CGPoint) {
        self.init(
            top: edges.contains(.top) ? value.y : .nan,
            leading: edges.contains(.leading) ? value.x : .nan,
            bottom: edges.contains(.bottom) ? value.y : .nan,
            trailing: edges.contains(.trailing) ? value.x : .nan
        )
    }
}


internal extension EnvironmentValues {
    var scrollPublisherID: AnyHashable? {
        get { self[ScrollPublisherIDKey.self] }
        set { self[ScrollPublisherIDKey.self] = newValue }
    }
}


private struct ScrollPublisherIDKey: EnvironmentKey {
    static let defaultValue: AnyHashable? = nil
}
