/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

internal struct ScrollOffsetValue: Equatable, Sendable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat
    
    subscript(edge: Edge) -> CGFloat {
        switch edge {
        case .top: top
        case .leading: leading
        case .bottom: bottom
        case .trailing: trailing
        }
    }
}
